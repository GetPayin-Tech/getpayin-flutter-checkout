# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `GetPayInPaymentSheet`: the same payment taken on a sheet in your own app, with a wallet
  button, the payer's saved cards, a card form and one pay button, running on PayLink's
  hosted card fields. The card number and security code are still rendered by the gateway,
  on a page you host at your registered origin; everything around them is Flutter. See
  [The payment sheet](doc/payment-sheet.md).
- `PayLinkFieldsSession`, `FieldsFailure`, `CardFieldsController`, `WalletSurface`,
  `buildFieldsPageHtml` and the `FieldsEvent` family, so a different sheet can be built from
  the same pieces.
- `CheckoutResultCode.checkoutUnavailable`, for a sheet that could not be shown at all with
  the fallback to the hosted checkout turned off. Nothing was charged and nothing was
  declined.
- `GetPayInCheckout.saveCard`: vault a card through a hosted tokenization run, read as a
  card save rather than as a payment. A verification authorizes one unit, vaults the card
  and releases the hold, so its invoice ends `VOIDED` and the payment rules would have
  called every successful save a failure. `CardSaveResult` says `saved`, `notSaved` or
  `cancelled`, and carries the verification's own state. The token is not on the return link
  and never reaches the app; it arrives with the `card_token.created` webhook. See
  [Saving a card](doc/saving-a-card.md).
- `invoiceIdInCheckoutUrl`, which reads the invoice id out of a `checkout_url` or
  `tokenization_url` so a run can be bound to its own result.
- `readReturnClaim`, the reading of a return link before any rule about what it may mean,
  which is what lets a card save and a payment share one parser.

### Changed

- The package is `getpayin_checkout`, so an app writes
  `import 'package:getpayin_checkout/getpayin_checkout.dart';`. It was
  `getpayin_flutter_checkout`, which said "Flutter" to an audience already writing Dart.
  Nothing else moved: the repository, the API and the behaviour are unchanged.
- The "no scripts" rule is now written against surfaces that can show a wallet rather than
  against the checkout view, which is what it always meant: the wallet surface and the
  hosted checkout are never scripted, and the sheet's card box is, deliberately.

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
