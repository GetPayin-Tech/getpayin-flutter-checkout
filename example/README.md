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

Android is scaffolded already, and its manifest carries the two things the package needs:
the `myapp` return scheme and the three `<queries>` entries that let Android's WebView find
a payment app. For iOS, run `flutter create --platforms=ios .` and add the scheme to
`Info.plist`. See [Setup](../doc/setup.md).

`myapp` has to match the **Mobile App Return Scheme** on your GetPayIn integration, or the
payment will work and the app will never hear about it.

## What to check on the phone

1. The switch shows which surface a build will use before you open anything.
2. With `googlePayInApp` off, an Android checkout opens in the browser sheet.
3. With it on, it opens in the app's own screen, and Google Pay appears only once Google
   has approved the app.
4. Closing the screen reports `cancelled`; a real payment reports `paid`, and only the
   `invoice.paid` webhook on your server proves it.
