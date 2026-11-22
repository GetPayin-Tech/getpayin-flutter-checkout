#!/usr/bin/env python3
"""The server half of the example, for trying a real payment on a real phone.

An app never creates a payment itself: `POST /api/v2/integration/init` is signed with the
integration's hash token, and anything that signs belongs on a server. This is the smallest
server that does it, so the phone only ever receives a `checkout_url`.

It is for testing, not for production. Run it on your machine, point the example app at it,
and keep the credentials in `~/.config/getpayin/dev.env`:

    GETPAYIN_BASE_URL=https://devpay.getpayin.com
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
import urllib.error
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
) -> dict:
    """Creates one payment and hands back the whole of what `/init` answered.

    The app is given the `data` block rather than a URL, so it can read the hosted-fields
    session out of it the way an integrator's app would.

    `mode` is not signed, so asking for hosted fields changes nothing about the signature.
    A company that does not have them answers 403 `fields_unavailable`, and rather than
    leave the tester with nothing, this asks again without them and says what happened.
    """
    payload: "OrderedDict[str, str]" = OrderedDict(
        (
            ("first_name", "Test"),
            ("last_name", "Payer"),
            ("email", "test.payer@example.com"),
            ("order_title", title),
            ("order_amount", amount),
            ("currency", currency),
        )
    )
    if hosted_fields:
        payload["mode"] = "fields"

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
            plain = create_payment(amount, currency, title, config, hosted_fields=False)
            plain["fields_error"] = refusal

            return plain

        raise RuntimeError(f"{failure.code} from {url}: {detail}") from failure

    return {"data": body.get("data", body), "fields_error": None}


def refused_code(detail: str) -> str | None:
    """The `code` a refusal carries, when it is one hosted fields can be refused with."""
    try:
        code = json.loads(detail).get("code")
    except json.JSONDecodeError:
        return None

    return code if code in {"fields_unavailable", "fields_unsupported", "origin_missing"} else None


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

    def do_GET(self) -> None:  # noqa: N802 - the name the server calls
        self._send(200, {"ok": True, "base_url": self.config["GETPAYIN_BASE_URL"]})

    def do_POST(self) -> None:  # noqa: N802 - the name the server calls
        length = int(self.headers.get("Content-Length") or 0)
        asked = json.loads(self.rfile.read(length) or b"{}")

        try:
            payment = create_payment(
                amount=str(asked.get("amount", "")).strip(),
                currency=str(asked.get("currency", "")).strip().upper(),
                title=str(asked.get("title") or "Example order"),
                config=self.config,
                hosted_fields=bool(asked.get("hosted_fields")),
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
