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

    python3 example/tool/dev_server.py                 # this computer only, port 8788
    HOST=0.0.0.0 python3 example/tool/dev_server.py    # also a phone on the same network

It signs with those credentials and takes none from the phone. Every call the app makes
carries the key it prints as it starts (`GETPAYIN_DEV_SERVER_KEY` in the same file keeps
one key across restarts), so nothing else that can reach it can ask it for payments, or
charge or revoke the cards it holds.
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


def forget_card(token: str) -> None:
    """Drops one card from the store, for a token that can no longer be charged."""
    kept = [c for c in read_cards() if c.get("card_token") != token]

    CARDS.parent.mkdir(parents=True, exist_ok=True)
    CARDS.write_text(json.dumps(kept, indent=2))
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

# The link each finished challenge was answered with. A reload of the return page, or the
# issuer posting twice, gets the same answer again: the charge is not pending any more,
# and "not pending" is not a decline.
FINISHED: dict[str, str] = {}


def data_of(answer: dict) -> dict:
    """The `data` block of a PayLink answer, or an empty one when it carried none."""
    data = answer.get("data")

    return data if isinstance(data, dict) else {}


def charge_card(asked: dict, config: dict[str, str]) -> tuple[int, dict]:
    """Charges a vaulted card, asking the issuer to authenticate the payer first.

    Hands back PayLink's own status with the answer. A refusal that reached the app as a
    success would be read as a payment: the app has nothing else to go on, and a declined
    charge announced as paid is the one mistake a payments harness must not make.

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

    # `reference`, not `reference_number`: /tokens/charge calls this field one thing and
    # /tokens/authentication/setup calls it the other. The signature covers the fields the
    # endpoint validates, so a name it does not know is dropped before PayLink signs and
    # the call comes back 422 "Invalid signature" -- which leaves the charge unauthenticated
    # rather than refused, and the payer is never asked for a passcode.
    setup_status, setup = call_tokens(
        "tokens/authentication/setup",
        OrderedDict((("card_token", card_token), ("reference", reference))),
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

    # Said out loud, because the charge goes through either way: an unauthenticated charge
    # is approved and settled, so the only thing that marks the difference is the passcode
    # the payer was never shown, and nobody notices a prompt that did not appear.
    if not authenticating:
        sys.stderr.write(
            f"not authenticating: public_base={public_base or 'none'} "
            f"setup={setup_status} {setup.get('message') or ''}\n"
        )

    if authenticating:
        charge["authentication_return_url"] = f"{public_base}/3ds/{reference}/return"
        charge["authentication_reference_id"] = setup["data"]["reference_id"]

        # Asked for only when the environment says PayLink understands the field, because
        # the signature covers every field sent: against a PayLink that does not validate
        # this one, it is dropped before PayLink signs and every charge comes back 422
        # "Invalid signature". Opt in with GETPAYIN_REQUEST_3DS_CHALLENGE=1 once the
        # backend that reads it is deployed.
        #
        # What it buys: without it the enrollment states no preference, CyberSource
        # defaults to "01", and the issuer takes the cheap answer -- a frictionless pass,
        # and a step-up nobody can try. The issuer may still refuse: it is a request.
        if config.get("GETPAYIN_REQUEST_3DS_CHALLENGE") == "1":
            charge["authentication_challenge"] = "mandate"

    status, answer = call_tokens("tokens/charge", charge, config)

    # PayLink records the payment after the gateway has charged, so a server error can
    # follow a charge. Handed on with a 200 it would read as a decline the payer can try
    # again after; raised, it reaches the app as a 502, which it reports as unconfirmed.
    if status >= 500:
        raise RuntimeError(f"PayLink answered {status}: the card may have been charged")

    if status != 202:
        # The invoice is the only handle on what the issuer decided. PayLink answers a
        # settled charge with no authentication fields at all, so whether this was a
        # frictionless pass or no authentication is a question for `payment_attempts.eci_raw`
        # on the PayLink side -- and that needs the invoice id this prints.
        sys.stderr.write(
            f"charge {status} invoice={data_of(answer).get('invoice_id')} "
            f"asked_the_issuer={bool(authenticating)}\n"
        )

        return status, answer | {"authenticated": authenticating}

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

    return status, {
        "success": False,
        "status": "requires_authentication",
        "challenge_url": f"{public_base}/3ds/{reference}",
        "invoice_id": data.get("invoice_id"),
    }


def revoke_card(asked: dict, config: dict[str, str]) -> dict:
    """Takes a vaulted card out of use, and forgets it here once PayLink has.

    Revoking is the payer asking for a card to be removed, so it is the one call here a
    real app's own backend would make on a tap rather than on a payment. PayLink answers
    the same way for a token it no longer holds as for one it has just taken away, so a
    store left out of step can be cleared by asking again.
    """
    token = str(asked.get("card_token", "")).strip()
    status, answer = call_tokens(
        "tokens/revoke", OrderedDict((("card_token", token),)), config
    )

    if status < 300 and answer.get("success"):
        forget_card(token)
        print(f"Revoked card token {token}")

    return answer


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
    if reference in FINISHED:
        return FINISHED[reference]

    pending = PENDING.pop(reference, None)

    if pending is None:
        return unconfirmed_link("This server is not waiting on that challenge")

    return_url = pending.get("return_url") or DEFAULT_RETURN_URL

    try:
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
    except Exception:  # noqa: BLE001 - no answer at all is as unknown as a server error
        link = unconfirmed_link(
            "PayLink did not answer: the card may have been charged",
            pending["invoice_id"],
            return_url,
        )
    else:
        link = completion_link(status, answer, pending["invoice_id"], return_url)

    FINISHED[reference] = link

    return link


def completion_link(
    status: int, answer: object, invoice_id: object, return_url: str = DEFAULT_RETURN_URL
) -> str:
    """The return link for PayLink's answer to a completed challenge.

    Only two answers say how it went: `success: true` with the invoice's paid status, and
    a 422 with `success: false`, which is a decline. The link carries PayLink's own paid
    status, so the package can refuse an invoice that is not paid in full. Anything else --
    a server error, an answer that names no invoice -- can follow the charge, because
    PayLink records the payment after the gateway answers, so it gets a link that says
    nothing about the outcome.
    """
    body = answer if isinstance(answer, dict) else {}
    data = body.get("data") if isinstance(body.get("data"), dict) else {}

    if status < 300 and body.get("success") is True and data.get("paid_status"):
        fields = {
            "success": "1",
            "invoice_id": str(data.get("invoice_id") or invoice_id),
            "invoice_status": str(data["paid_status"]),
            "message": "Charged the saved card.",
        }
    elif status == 422 and body.get("success") is False:
        fields = {
            "success": "0",
            "invoice_id": str(invoice_id),
            "invoice_status": "UNPAID",
            "message": str(body.get("message") or "The bank did not approve it."),
        }
    else:
        return unconfirmed_link(
            f"PayLink answered {status}: the card may have been charged",
            invoice_id,
            return_url,
        )

    return return_url + "?" + urllib.parse.urlencode(fields)


def unconfirmed_link(
    reason: str, invoice_id: object = None, return_url: str = DEFAULT_RETURN_URL
) -> str:
    """A return link that says nothing about how the charge ended.

    There is no link for "nobody knows". The package reads one without `success` as
    unreadable and closes the sheet, where `success=0` would offer the payer another try on
    a card that may have been charged. It names the invoice when there is one: a browser
    sheet bound to that invoice passes over a link that names none.
    """
    fields = {"message": reason}

    if invoice_id is not None:
        fields["invoice_id"] = str(invoice_id)

    return return_url + "?" + urllib.parse.urlencode(fields)


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

    # The key every call from the app carries. The routes a browser or PayLink reaches -- the
    # fields page, the bank's challenge and the webhook -- cannot carry it and do not ask.
    key: str = ""

    def _from_the_app(self) -> bool:
        """True when the request carries this server's key; answers 401 when it does not."""
        given = self.headers.get("X-Dev-Server-Key", "")

        if self.key and hmac.compare_digest(given.encode(), self.key.encode()):
            return True

        self._send(401, {"error": "Missing or wrong X-Dev-Server-Key."})

        return False

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

        if not self._from_the_app():
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
            status, answer = charge_card(asked, self.config)
        except Exception as failure:  # noqa: BLE001 - the app is told whatever went wrong
            self._send(502, {"error": str(failure)})

            return

        # A challenge is an answer, not a failure: the app reads `challenge_url` and sends
        # the payer to their bank. Everything else carries PayLink's own verdict, because a
        # refusal flattened to 200 is what makes a declined charge look like a payment.
        self._send(200 if answer.get("challenge_url") or answer.get("success") else 422, answer)

    def _revoke(self, asked: dict) -> None:
        """Revokes a vaulted card, which is a call only something holding the token can make."""
        try:
            answer = revoke_card(asked, self.config)
        except Exception as failure:  # noqa: BLE001 - the app is told whatever went wrong
            self._send(502, {"error": str(failure)})

            return

        self._send(200, answer)

    def do_POST(self) -> None:  # noqa: N802 - the name the server calls
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)

        try:
            asked = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            asked = {}

        if self.path.startswith("/charge"):
            if self._from_the_app():
                self._charge(asked)

            return

        if self.path.startswith("/revoke"):
            if self._from_the_app():
                self._revoke(asked)

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

        if not self._from_the_app():
            return

        try:
            payment = create_payment(
                amount=str(asked.get("amount", "")).strip(),
                currency=str(asked.get("currency", "")).strip().upper(),
                title=str(asked.get("title") or "Example order"),
                config=self.config,
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
    """Serves until it is stopped.

    On this computer only unless `HOST` says otherwise: a tunnel on the same machine reaches
    it there, and a phone on the network needs `HOST=0.0.0.0`.
    """
    Handler.config = configuration()
    Handler.key = Handler.config.get("GETPAYIN_DEV_SERVER_KEY") or secrets.token_urlsafe(18)
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8788"))
    server = HTTPServer((host, port), Handler)
    address = lan_address() if host == "0.0.0.0" else host

    print(f"Point the example app at http://{address}:{port}")
    print(f"Server key for the app: {Handler.key}")
    print(f"Creating payments on {Handler.config['GETPAYIN_BASE_URL']}")
    server.serve_forever()


if __name__ == "__main__":
    main()
