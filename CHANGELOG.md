# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `CheckoutResultCode.outcomeUnknown`, for a charge that went out and whose answer never
  came back — the network went, the page died, your own server threw after it had called.
  The one result that is neither a payment nor a refusal: read the invoice, and never take
  payment again on it.
- `PaymentSheetStrings.outcomeUnknown`, which is what the payer is told in that case. Never
  "try another card": the card may already have been charged.

### Fixed

Five faults in the payment sheet, each found by a review and each fixed after the test that
proves it was there. All five end the same way: a payer invited to pay a second time for a
card that may already have been charged.

- A sheet closed mid-charge reported `cancelled`, which the docs said to do nothing about,
  while PayLink went on and took the payment it already had. A swipe, a tap above the sheet
  and Android Back are all refused now from the moment a charge or an issuer challenge is
  out, and allowed again as soon as one is not.
- An error the page could not name, arriving after the charge had gone out, was read as
  "the card fields cannot run here": the payer was handed to the hosted checkout and could
  pay a second time. Nothing falls back once a charge is out; the sheet settles not paid
  with `outcomeUnknown` instead.
- The sheet never held the one-checkout-at-a-time guard, so a double tap opened two of them
  and `GetPayInCheckout.busy` stayed false, although the docs tell integrators to guard the
  pay button with it. It is held for as long as the sheet is open, and released before the
  hosted fallback opens a checkout of its own.
- A payer whose wallet payment was declined could try again, and the second answer went
  nowhere: the surface had already finished with its return link and would not report
  another. It is rebuilt after a decline, so the next attempt is read like the first.
- An exception from `chargeSavedCard` offered the payer another card, although a timeout
  from a server that had already charged the card is one of those exceptions. The sheet
  settles with `outcomeUnknown` instead of inviting a second payment.

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
- `GetPayInPaymentSheet`: the same payment taken on a sheet in your own app, with a wallet
  button, the payer's saved cards, a card form and one pay button, running on PayLink's
  hosted card fields. The card number and security code are still rendered by the gateway,
  on a page you host at your registered origin; everything around them is Flutter. See
  [The payment sheet](doc/payment-sheet.md).
- `PayLinkFieldsSession`, `FieldsFailure`, `CardFieldsController`, `WalletSurface`,
  `buildFieldsPageHtml` and the `FieldsEvent` family, so a different sheet can be built from
  the same pieces.
- `CardFieldsSnapshot` and `applyFieldsEvent`: what the card box knows is a value, and what
  an event means to it is a pure function over that value.
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

### Notes

- The frame rule holds on both platforms here, not iOS only: `webview_flutter` reports
  whether a navigation came from the main frame on Android as well.
- `expectedInvoiceId: null` means "no invoice to bind to". Dart cannot tell that apart from
  a field your server left out of its JSON, so make your server always send the invoice id.
