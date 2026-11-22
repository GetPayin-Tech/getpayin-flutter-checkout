# Example

A harness for the checks that only a phone can make, and the thing the `apk` workflow
builds.

There is no server here on purpose. Paste a `checkout_url` that your own server or the
GetPayIn dashboard has already created, and the app opens it exactly as an integration
would: same provider, same options, same reading of the result. The invoice id is read off
the URL, so the result is still bound to the checkout it came from.

```bash
cd example
flutter run
```

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
