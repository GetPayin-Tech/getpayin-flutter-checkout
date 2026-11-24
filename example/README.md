# Example

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

python3 example/tool/dev_server.py      # prints the address to put in the app
cd example && flutter run
```

Keep that file out of the repository. If a hash token ever reaches a bundle, a page or a
log, rotate it.

## Putting it on a phone

The `apk` workflow builds the debug APK. Both addresses the harness needs are built in
rather than typed on a phone, and neither is committed:

```bash
gh workflow run apk.yml \
  -f payments_server=http://192.168.1.5:8788 \
  -f fields_page=https://your-origin.example.com/paylink-fields.html
```

`payments_server` is `tool/dev_server.py` as the **phone** reaches it, so a LAN address,
not `localhost`. `fields_page` is only for the payment sheet, and only works from the
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
it treats everything that is not `/init` or `/charge` as the webhook — and it keeps what
arrives in `~/.config/getpayin/dev-cards.json`.

The next payment then offers that card on the sheet. Picking it calls `/charge` here, which
signs `tokens/charge` with the hash token and answers. The payer types nothing and the app
never sees the token, which is the whole point of a vaulted card.

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
