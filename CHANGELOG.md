# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0

First release: the Flutter port of
[`@getpayin/expo-checkout`](https://www.npmjs.com/package/@getpayin/expo-checkout), with the
same checkout, the same return-link rules and the same security model.

### Added

- `GetPayInCheckout.open`, `presentationFor` and `busy`.
- `GetPayInProvider`, which presents the checkout as a full-screen route on the app's own
  `Navigator`, so the system back button closes it.
- `GetPayInCheckoutView`, for putting the checkout in a screen of your own.
- `declareHostAppSchemes`, which replaces the Expo package's reading of `app.json`: Flutter
  has no app config to read at runtime.
- `PaymentReturnRedirect`, for keeping `go_router` from opening the return link as a route.
- Google Pay in the app's own screen through
  `AndroidWebViewController.setPaymentRequestEnabled`, applied before the page loads.
- The browser-sheet presentation on `url_launcher`, with the sheet's dismissal read from the
  app's own lifecycle and a grace period for a return link that races it.

### Notes

- The frame rule holds on both platforms here, not iOS only: `webview_flutter` reports
  whether a navigation came from the main frame on Android as well.
- `expectedInvoiceId: null` means "no invoice to bind to". Dart cannot tell that apart from
  a field your server left out of its JSON, so make your server always send the invoice id.
