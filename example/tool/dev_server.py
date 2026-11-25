#!/usr/bin/env python3
"""The server half of the example, for trying a real payment on a real phone.

An app never creates a payment itself: `POST /api/v2/integration/init` is signed with the
integration's hash token, and anything that signs belongs on a server. This is the smallest
server that does it, so the phone only ever receives a `checkout_url`.

It is for testing, not for production. Run it on your machine, point the example app at it,
and keep the credentials in `~/.config/getpayin/dev.env`:

    GETPAYIN_BASE_URL=https://pay.getpayin.com
    GETPAYIN_PUBLIC_TOKEN=...
    GETPAYIN_HASH_TOKEN=...

    python3 example/tool/dev_server.py            # serves on the LAN, port 8788
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import socket
import ssl
import sys
import secrets
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

CONFIG = Path.home() / ".config" / "getpayin" / "dev.env"

# The API sits behind an edge that answers 1010 to a default urllib signature, so the
# harness names itself like anything else that speaks HTTP.
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0 Safari/537.36"
)

# The fields `/init` signs, in the order its own validator reads them. The signature is a
# concatenation of the values, so the order has to match or the API answers "Invalid
# signature" and says nothing else.
SIGNED_FIELDS = (
    "first_name",
    "last_name",
    "email",
    "order_title",
    "order_amount",
    "currency",
)


def configuration() -> dict[str, str]:
    """The base URL and the two tokens, from the environment or the config file."""
    values = {}

    if CONFIG.exists():
        for line in CONFIG.read_text().splitlines():
            if line.strip() and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip()

    values.update({k: v for k, v in os.environ.items() if k.startswith("GETPAYIN_")})

    missing = [
        key
        for key in ("GETPAYIN_BASE_URL", "GETPAYIN_PUBLIC_TOKEN", "GETPAYIN_HASH_TOKEN")
        if not values.get(key)
    ]

    if missing:
        sys.exit(f"Missing {', '.join(missing)}. Put them in {CONFIG}.")

    return values


def sign(payload: "OrderedDict[str, str]", hash_token: str) -> str:
    """The signature `/init` expects over [payload].

    Base64 of an HMAC-SHA256 over the signed values run together, which is what the
    integration's own validator rebuilds on the other side.
    """
    joined = "".join(str(payload[field]) for field in SIGNED_FIELDS if field in payload)
    digest = hmac.new(hash_token.encode(), joined.encode(), hashlib.sha256).digest()

    return base64.b64encode(digest).decode()


def create_payment(
    amount: str,
    currency: str,
    title: str,
    config: dict[str, str],
    hosted_fields: bool = False,
    tokenize: bool = False,
    first_name: str = "Test",
    last_name: str = "Payer",
    email: str = "test.payer@example.com",
    consent_text: str = "",
) -> dict:
    """Creates one payment and hands back the whole of what `/init` answered.

    The app is given the `data` block rather than a URL, so it can read the hosted-fields
    session out of it the way an integrator's app would.

    Neither `mode` nor `tokenize` is signed, so asking for hosted fields, or for the card to
    be kept for next time, changes nothing about the signature.
    A company that does not have them answers 403 `fields_unavailable`, and rather than
    leave the tester with nothing, this asks again without them and says what happened.
    """
    payload: "OrderedDict[str, str]" = OrderedDict(
        (
            ("first_name", first_name),
            ("last_name", last_name),
            ("email", email),
            ("order_title", title),
            ("order_amount", amount),
            ("currency", currency),
        )
    )
    if hosted_fields:
        payload["mode"] = "fields"

    if tokenize:
        payload["tokenize"] = True

    # Required with mode "fields": on the integrator's own form there is no consent box of
    # PayLink's, so the wording shown is what gets stored and relied on in a dispute. Like
    # `tokenize`, it is outside the signature.
    if consent_text:
        payload["tokenization_consent_text"] = consent_text

    payload["token"] = config["GETPAYIN_PUBLIC_TOKEN"]
    payload["signature"] = sign(payload, config["GETPAYIN_HASH_TOKEN"])

    url = config["GETPAYIN_BASE_URL"].rstrip("/") + "/api/v2/integration/init"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            # The edge in front of the API refuses a default urllib signature with a 1010.
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30, context=ssl.create_default_context()) as answer:
            body = json.loads(answer.read().decode())
    except urllib.error.HTTPError as failure:
        detail = failure.read().decode()[:500]
        refusal = refused_code(detail)

        if hosted_fields and refusal:
            plain = create_payment(
                amount,
                currency,
                title,
                config,
                hosted_fields=False,
                tokenize=tokenize,
                first_name=first_name,
                last_name=last_name,
                email=email,
                consent_text=consent_text,
            )
            plain["fields_error"] = refusal

            return plain

        raise RuntimeError(f"{failure.code} from {url}: {detail}") from failure

    return {"data": body.get("data", body), "fields_error": None}


# Refusals that mean "take this payment on the hosted checkout instead", rather than
# "this payment cannot be taken". `tokenize_unavailable_on_fields` is among them by design:
# keeping a card needs consent wording PayLink can evidence, and on a page the integrator
# owns there is nothing it could show or stand behind.
FALLS_BACK_TO_CHECKOUT = {
    "fields_unavailable",
    "fields_unsupported",
    "origin_missing",
    # A PayLink that cannot keep a card from hosted fields refuses it outright. One that
    # can refuses it only when the consent wording was left out.
    "tokenize_unavailable_on_fields",
    "tokenize_consent_required",
}


CARDS = CONFIG.parent / "dev-cards.json"


def read_cards() -> list[dict]:
    """The cards this harness has been told about, newest first."""
    try:
        return json.loads(CARDS.read_text())
    except (OSError, json.JSONDecodeError):
        return []


def remember_card(card: dict) -> None:
    """Keeps one card, replacing any earlier record of the same token."""
    kept = [c for c in read_cards() if c.get("card_token") != card.get("card_token")]

    CARDS.parent.mkdir(parents=True, exist_ok=True)
    CARDS.write_text(json.dumps([card] + kept, indent=2))
    CARDS.chmod(0o600)


def call_tokens(path: str, payload: "OrderedDict[str, str]", config: dict[str, str]) -> tuple[int, dict]:
    """Signs a tokens/* call and makes it, handing back the status with the body.

    The signature covers every field except itself and the public token, in the order they
    are sent -- so the order each caller builds is part of the contract, not a style choice.
    A 202 is an answer rather than a failure: the charge is alive and waiting on the payer,
    so the status comes back instead of an exception.
    """
    signed = "".join(str(value) for value in payload.values())
    digest = hmac.new(
        config["GETPAYIN_HASH_TOKEN"].encode(), signed.encode(), hashlib.sha256
    ).digest()

    payload["token"] = config["GETPAYIN_PUBLIC_TOKEN"]
    payload["signature"] = base64.b64encode(digest).decode()

    url = config["GETPAYIN_BASE_URL"].rstrip("/") + "/api/v2/integration/" + path
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=30, context=ssl.create_default_context()) as answer:
            return answer.status, json.loads(answer.read().decode())
    except urllib.error.HTTPError as failure:
        body = failure.read().decode()

        try:
            return failure.code, json.loads(body)
        except json.JSONDecodeError:
            raise RuntimeError(f"{failure.code} from {url}: {body[:400]}") from failure


# Charges paused mid-flight, waiting on the payer to answer their bank. Held in memory
# only: a challenge that outlives this process is one nobody is still looking at.
PENDING: dict[str, dict] = {}

# Where a finished challenge sends the payer when the charge named nowhere. This app's own
# link, because it is the app this server was written for. Another app driving the same
# server sends `return_url` on the charge and is sent back to its own scheme instead: a
# link to an app the phone does not have goes nowhere at all.
DEFAULT_RETURN_URL = "myapp://payment-return"


def charge_card(asked: dict, config: dict[str, str]) -> dict:
    """Charges a vaulted card, asking the issuer to authenticate the payer first.

    Three calls rather than one, because a charge sent without an authentication return URL
    is never challenged: the issuer is not asked, and the payment goes through on the
    strength of the card having been authenticated once, when it was vaulted. Sending them
    lets the issuer stop the charge at 202 and ask for a passcode.

    The challenge is run over [public_base] rather than this server's LAN address: the
    issuer's page is HTTPS and posts its answer back to the return URL, and a browser will
    not carry that answer down to plain HTTP.
    """
    card_token = str(asked.get("card_token", "")).strip()
    public_base = str(asked.get("public_base", "")).strip().rstrip("/")
    reference = secrets.token_hex(8)

    setup_status, setup = call_tokens(
        "tokens/authentication/setup",
        OrderedDict((("card_token", card_token), ("reference_number", reference))),
        config,
    )

    charge: "OrderedDict[str, str]" = OrderedDict(
        (
            ("card_token", card_token),
            ("initiator", "customer"),
            ("currency", str(asked.get("currency", "")).strip().upper()),
            ("price", str(asked.get("amount", "")).strip()),
            ("product", str(asked.get("title") or "Example order")),
        )
    )

    # Both or neither: PayLink requires each with the other, and without them the issuer is
    # never asked. Skipped when there is nowhere public to send the payer back to.
    authenticating = bool(public_base) and setup_status < 300 and setup.get("success")

    if authenticating:
        charge["authentication_return_url"] = f"{public_base}/3ds/{reference}/return"
        charge["authentication_reference_id"] = setup["data"]["reference_id"]

    status, answer = call_tokens("tokens/charge", charge, config)

    if status != 202:
        return answer | {"authenticated": authenticating}

    data = answer.get("data", {})

    PENDING[reference] = {
        "card_token": data.get("card_token") or card_token,
        "invoice_id": data.get("invoice_id"),
        "step_up_url": data.get("step_up_url"),
        "access_token": data.get("access_token"),
        "authentication_transaction_id": data.get("authentication_transaction_id"),
        "return_url": str(asked.get("return_url") or DEFAULT_RETURN_URL).strip(),
        "config": config,
    }

    return {
        "success": False,
        "status": "requires_authentication",
        "challenge_url": f"{public_base}/3ds/{reference}",
        "invoice_id": data.get("invoice_id"),
    }


def step_up_page(pending: dict) -> str:
    """The page that puts the issuer's passcode form in front of the payer.

    The issuer will only render it for a form POST carrying the access token, so the page
    exists to make that POST. It posts to the top level rather than into a frame: the answer
    comes back as a navigation to the return URL, which is what finishes the charge.
    """
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Your bank</title>
<style>
  body {{ margin:0; font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
         color:#30313d; display:flex; align-items:center; justify-content:center; height:100vh; }}
</style></head>
<body>
  <p>Contacting your bank&hellip;</p>
  <form id="stepUp" method="post" action="{pending['step_up_url']}">
    <input type="hidden" name="JWT" value="{pending['access_token']}">
  </form>
  <script>document.getElementById('stepUp').submit();</script>
</body></html>"""


def finish_authentication(reference: str) -> str:
    """Completes a challenged charge and hands the app its answer as a return link.

    The link is the one the hosted checkout sends an app back on, so the package reads it
    with the rules it already has. It is this server asserting the outcome, not PayLink --
    which is why the app treats a result as a report and the webhook as the proof.
    """
    pending = PENDING.pop(reference, None)

    if pending is None:
        return f"{DEFAULT_RETURN_URL}?success=0&message=That+challenge+has+already+been+answered"

    status, answer = call_tokens(
        "tokens/authentication/complete",
        OrderedDict(
            (
                ("card_token", pending["card_token"]),
                ("invoice_id", str(pending["invoice_id"])),
                ("authentication_transaction_id", pending["authentication_transaction_id"]),
            )
        ),
        pending["config"],
    )

    paid = status < 300 and answer.get("success")
    fields = {
        "success": "1" if paid else "0",
        "invoice_id": str(pending["invoice_id"]),
        "invoice_status": "PAID" if paid else "UNPAID",
        "message": str(answer.get("message") or ("Charged the saved card." if paid else "The bank did not approve it.")),
    }

    return pending["return_url"] + "?" + urllib.parse.urlencode(fields)


def refused_code(detail: str) -> str | None:
    """The `code` a refusal carries, when it is one hosted fields can be refused with."""
    try:
        code = json.loads(detail).get("code")
    except json.JSONDecodeError:
        return None

    return code if code in FALLS_BACK_TO_CHECKOUT else None


class Handler(BaseHTTPRequestHandler):
    """Answers the one question the app asks: make me a payment."""

    config: dict[str, str] = {}

    def _send(self, status: int, body: dict) -> None:
        encoded = json.dumps(body).encode()

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_html(self, html: str, status: int = 200) -> None:
        encoded = html.encode()

        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _send_to_app(self, link: str) -> None:
        """Sends the payer's browser back to the app on a return link."""
        self.send_response(303)
        self.send_header("Location", link)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802 - the name the server calls
        if self.path.startswith("/3ds/"):
            self._three_d_secure()

            return

        if self.path.startswith("/paylink-fields.html"):
            self._send_page()

            return

        if self.path.startswith("/cards"):
            self._send(200, {"cards": read_cards()})

            return

        self._send(200, {"ok": True, "base_url": self.config["GETPAYIN_BASE_URL"]})

    def _three_d_secure(self) -> None:
        """The two halves of a challenge: the page that raises it, and the answer coming back.

        Both arrive on the payer's browser rather than from the app, which is why they are
        GET routes on whatever host the challenge was started on.
        """
        parts = self.path.split("?")[0].strip("/").split("/")
        reference = parts[1] if len(parts) > 1 else ""

        if parts[-1] == "return":
            self._send_to_app(finish_authentication(reference))

            return

        pending = PENDING.get(reference)

        if pending is None:
            self._send_html("<p>That challenge is no longer waiting.</p>", 404)

            return

        self._send_html(step_up_page(pending))

    def _send_page(self) -> None:
        """Serves the card fields page, pointed at whichever PayLink this server uses.

        Served from here so one tunnel covers the page, the webhook and the charge: the
        origin registered on the integration has to serve the page, and the webhook has to
        arrive at the same host. A second server for the page is a second thing to get
        wrong.
        """
        page = (Path(__file__).resolve().parents[2] / "doc" / "paylink-fields.html")
        html = page.read_text().replace(
            "<YOUR-PAYLINK-HOST>", self.config["GETPAYIN_BASE_URL"].rstrip("/")
        )
        encoded = html.encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _webhook(self, asked: dict) -> None:
        """Keeps the card a `card_token.created` webhook delivers.

        The token itself only ever arrives here. It never reaches the app and never should:
        a vaulted card is charged with the hash token, which is what makes this a server.
        """
        data = asked.get("data") if isinstance(asked.get("data"), dict) else asked

        if data.get("card_token"):
            remember_card(
                {
                    "card_token": data.get("card_token"),
                    "brand": data.get("card_brand"),
                    "last4": data.get("card_last4"),
                    "expiry_month": data.get("card_expiry_month") or data.get("expiry_month"),
                    "expiry_year": data.get("card_expiry_year") or data.get("expiry_year"),
                    "invoice_id": data.get("invoice_id"),
                }
            )
            print(f"Kept card ending {data.get('card_last4')} from invoice {data.get('invoice_id')}")

        self._send(200, {"ok": True})

    def _charge(self, asked: dict) -> None:
        """Charges a card this harness was told about, the way a real backend would."""
        try:
            answer = charge_card(asked, self._credentials(asked))
        except Exception as failure:  # noqa: BLE001 - the app is told whatever went wrong
            self._send(502, {"error": str(failure)})

            return

        self._send(200, answer)

    def _credentials(self, asked: dict) -> dict[str, str]:
        """This server's own credentials, with anything the app sent taking precedence.

        The harness can be pointed at another integration from the phone, so a tester does
        not have to edit a file and restart to try a second account. Empty values are
        ignored rather than honoured: a blank field in the app means "leave it alone", not
        "sign with nothing".
        """
        overrides = {
            "GETPAYIN_BASE_URL": str(asked.get("base_url") or "").strip(),
            "GETPAYIN_PUBLIC_TOKEN": str(asked.get("public_token") or "").strip(),
            "GETPAYIN_HASH_TOKEN": str(asked.get("hash_token") or "").strip(),
        }

        return self.config | {k: v for k, v in overrides.items() if v}

    def do_POST(self) -> None:  # noqa: N802 - the name the server calls
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)

        try:
            asked = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            asked = {}

        if self.path.startswith("/charge"):
            self._charge(asked)

            return

        # The issuer posts its answer rather than following a link, so the return URL has to
        # take a POST as readily as a GET.
        if self.path.startswith("/3ds/"):
            self._send_to_app(
                finish_authentication(self.path.split("?")[0].strip("/").split("/")[1])
            )

            return

        # Anything that is not /init or /charge is treated as the webhook, because the URL
        # on the integration is whatever the dashboard was set to and this server would
        # rather receive the card than be right about the path.
        if not self.path.startswith("/init") and self.path != "/":
            self._webhook(asked)

            return

        try:
            payment = create_payment(
                amount=str(asked.get("amount", "")).strip(),
                currency=str(asked.get("currency", "")).strip().upper(),
                title=str(asked.get("title") or "Example order"),
                config=self._credentials(asked),
                hosted_fields=bool(asked.get("hosted_fields")),
                tokenize=bool(asked.get("tokenize")),
                first_name=str(asked.get("first_name") or "Test"),
                last_name=str(asked.get("last_name") or "Payer"),
                email=str(asked.get("email") or "test.payer@example.com"),
                consent_text=str(asked.get("tokenization_consent_text") or ""),
            )
        except Exception as failure:  # noqa: BLE001 - the app is told whatever went wrong
            self._send(502, {"error": str(failure)})

            return

        self._send(201, payment)

    def log_message(self, format: str, *args) -> None:  # noqa: A002 - the name the server calls
        sys.stderr.write(f"{self.address_string()} {format % args}\n")


def lan_address() -> str:
    """This machine's address on the network the phone is also on."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        probe.connect(("192.168.1.1", 1))

        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def main() -> None:
    """Serves until it is stopped."""
    Handler.config = configuration()
    port = int(os.environ.get("PORT", "8788"))
    server = HTTPServer(("0.0.0.0", port), Handler)

    print(f"Point the example app at http://{lan_address()}:{port}")
    print(f"Creating payments on {Handler.config['GETPAYIN_BASE_URL']}")
    server.serve_forever()


if __name__ == "__main__":
    main()
