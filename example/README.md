# Example

Your server creates the payment and gives the app its `checkout_url` and invoice id. The app
opens the checkout and reads the result.

```dart
import 'package:flutter/material.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

void main() {
  declareHostAppSchemes(const ['myapp']);
  runApp(MaterialApp(home: GetPayInProvider(child: const ShopPage())));
}

/// Takes one payment. `payment` comes from your own server, which called
/// `POST /api/v2/integration/init`.
Future<void> pay(Payment payment) async {
  final result = await GetPayInCheckout.open(
    payment.checkoutUrl,
    OpenCheckoutOptions(
      returnUrl: 'myapp://payment-return',
      expectedInvoiceId: payment.invoiceId,
    ),
  );

  if (result.status == CheckoutStatus.paid) {
    // Deliver the order only once your server has the invoice.paid webhook.
  }
}
```

[Setup](../doc/setup.md) covers the return scheme and the server, and
[Taking payments](../doc/taking-payments.md) covers every result.

## The test app in this folder

A harness for the checks that only a phone can make, and the thing the `apk` workflow
builds.

Give it an amount and a currency and it creates a payment, then opens it exactly as an
integration would: same provider, same options, same reading of the result. The invoice id
is read off the `checkout_url`, so the result stays bound to the checkout it came from.

The app does not create the payment itself, and no app should: `POST /v2/integration/init`
is signed with the integration's **hash token**, and anything that signs belongs on a
server. `tool/dev_server.py` is the smallest server that does it, so the phone only ever
receives a link.

```bash
# on your machine, once
cat > ~/.config/getpayin/dev.env <<'ENV'
GETPAYIN_BASE_URL=https://pay.getpayin.com
GETPAYIN_PUBLIC_TOKEN=your-authentication-token
GETPAYIN_HASH_TOKEN=your-hash-token
ENV
chmod 600 ~/.config/getpayin/dev.env

python3 example/tool/dev_server.py      # prints its address and its key
cd example && flutter run
```

Keep that file out of the repository. If a hash token ever reaches a bundle, a page or a
log, rotate it.

The server signs with those credentials and takes none from the phone, so no token is ever
typed into the app. Every call the app makes carries the key the server prints as it
starts: type it under the gear, or build it in with `--dart-define=DEV_SERVER_KEY=...`. Add
`GETPAYIN_DEV_SERVER_KEY=...` to `dev.env` to keep one key across restarts.

It listens on this computer only, which is all a tunnel on the same machine needs. For a
phone on the same network, start it with `HOST=0.0.0.0`, and only on a network you trust.

## Putting it on a phone

The `apk` workflow builds the debug APK. Both addresses the harness needs are built in
rather than typed on a phone, and neither is committed:

```bash
gh workflow run apk.yml \
  -f payments_server=http://192.168.1.5:8788 \
  -f fields_page=https://your-origin.example.com/paylink-fields.html
```

`payments_server` is `tool/dev_server.py` as the **phone** reaches it, so a LAN address
(with the server started as `HOST=0.0.0.0`) or the tunnel, not `localhost`. `fields_page` is only for the payment sheet, and only works from the
origin registered for the integration. Leave either out and the field starts empty or on
its default, and you type it on the phone.

Locally the same two go through `--dart-define`:

```bash
cd example && flutter run --dart-define=PAYMENTS_SERVER=http://192.168.1.5:8788
```

Android is scaffolded already, and its manifest carries the two things the package needs:
the `myapp` return scheme and the three `<queries>` entries that let Android's WebView find
a payment app. For iOS, run `flutter create --platforms=ios .` and add the scheme to
`Info.plist`. See [Setup](../doc/setup.md).

`myapp` has to match the **Mobile App Return Scheme** on your GetPayIn integration, or the
payment will work and the app will never hear about it.

## Charging a card it saved

Tick **Save my card for future payments** and the card is vaulted off the same
authorization. The token itself never reaches the app: PayLink sends it to the integration's
**Webhook URL** as `card_token.created`, so point that at this server — any path will do,
it treats every POST that is not `/init`, `/charge` or `/revoke` as the webhook — and it keeps what
arrives in `~/.config/getpayin/dev-cards.json`.

The next payment then offers that card on the sheet. Picking it calls `/charge` here, which
signs `tokens/charge` with the hash token and answers. The payer types nothing and the app
never sees the token, which is the whole point of a vaulted card.

The charge asks the issuer to authenticate the payer, which takes three calls rather than
one: `tokens/authentication/setup`, then `tokens/charge` carrying an
`authentication_return_url`, then `tokens/authentication/complete` once the payer has
answered. Without those fields the issuer is never asked and the charge simply goes through
on the strength of the card having been authenticated when it was vaulted -- which is the
documented default, not a fault.

Set `GETPAYIN_REQUEST_3DS_CHALLENGE=1` in `dev.env` and the charge also carries
`authentication_challenge: "mandate"`, which asks the issuer for a passcode rather than
leaving the choice to them. Left out, the enrollment states no preference, CyberSource
applies its own default, and an issuer with a card it recognises almost always passes the
payer through without asking anything -- so the step-up is never seen and never tested. The
issuer may still decline to challenge: it is a request, not a switch.

It is opt-in because the signature covers every field sent. A PayLink that does not know
this field drops it before signing, the two strings disagree, and **every token charge comes
back `422 Invalid signature`** -- so turn it on only once the backend that reads it is
deployed.

The challenge runs over the tunnel rather than this server's LAN address. A bank's page is
HTTPS and posts its answer back to the return URL, and no browser will carry that answer
down to plain HTTP.

The finished challenge is handed back as a return link, by default this app's own
`myapp://payment-return`. An app of your own driving this server sends `return_url` on the
charge and is sent back to its own scheme instead, because a link to an app the phone does
not have goes nowhere at all.

A card the payer no longer wants is removed the same way it is charged: the screen lists
every card this server is holding, **Remove** posts the token to `/revoke` here, and that
signs `tokens/revoke` with the hash token and forgets the card once PayLink has taken it
away. Asking twice is harmless -- a token PayLink no longer holds is answered like one it
has just revoked -- so a list left out of step is cleared by asking again.

This server also serves the fields page at `/paylink-fields.html`, pointed at whichever
PayLink it is configured for, so one tunnel covers the page, the webhook and the charge:

```bash
ngrok http --url=https://your-reserved-domain 127.0.0.1:8788
```

## What to check on the phone

1. The switch shows which surface a build will use before you open anything.
2. With `googlePayInApp` off, an Android checkout opens in the browser sheet.
3. With it on, it opens in the app's own screen, and Google Pay appears only once Google
   has approved the app.
4. Closing the screen reports `cancelled`; a real payment reports `paid`, and only the
   `invoice.paid` webhook on your server proves it.
