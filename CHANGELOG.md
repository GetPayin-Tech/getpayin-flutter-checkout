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
  `Navigator`, so the system back button closes it. A checkout screen your app takes away in
  its own code settles as `cancelled`: with `closedByAppMessage`, or with
  `closedByUnmountMessage` when the provider went with it. After a failure once the page
  had loaded, it settles `outcomeUnknown` instead.
- `GetPayInCheckoutView`, for putting the checkout in a screen of your own. `onPageLoaded`
  tells a failure that may follow a charge from one before the checkout ever loaded.
- `declareHostAppSchemes`, which replaces the Expo package's reading of `app.json`: Flutter
  has no app config to read at runtime.
- `PaymentReturnRedirect`, for keeping `go_router` from opening the return link as a route.
- Google Pay in the app's own screen through
  `AndroidWebViewController.setPaymentRequestEnabled`, applied before the page loads.
- The browser-sheet presentation on `url_launcher`, with the sheet's dismissal read from the
  app's own lifecycle and a grace period for a return link that races it.
- `GetPayInPaymentSheet.show`: the same payment taken on a sheet in your own app, with a wallet
  button, the payer's saved cards, a card form and one pay button, running on PayLink's
  hosted card fields. The card number and security code are still rendered by the gateway,
  on a page you host at your registered origin; everything around them is Flutter. See
  [The payment sheet](doc/payment-sheet.md).
- `PayLinkFieldsSession`, `FieldsFailure`, `CardFieldsController`, `WalletSurface`,
  `buildFieldsPageHtml` and the `FieldsEvent` family, so a different sheet can be built from
  the same pieces. `FieldsFailure` names every code PayLink's fields send, `already_paid`,
  `not_payable` and `expired` included; `WalletSurface.onCharging` says when a wallet charge
  is out, and `onChargingAfterLeaving` when it was marked as the button left the screen;
  `FieldsPayment.attempt` is the code that ties an answer to the charge it answers, and
  `FieldsError.attempt` ties a failure during a charge to it the same way.
- `CardFieldsSnapshot` and `applyFieldsEvent`: what the card box knows is a value, and what
  an event means to it is a pure function over that value.
- `CheckoutResultCode.checkoutUnavailable`, for a sheet that could not be shown at all with
  the fallback to the hosted checkout turned off. Nothing was charged and nothing was
  declined.
- `CheckoutResultCode.outcomeUnknown`, for a charge that went out and whose answer never
  came back — the network went, the page died, the payer closed the sheet mid-charge, your
  own server threw after it had called — and for an invoice PayLink says is already paid.
  The one result that is neither a payment nor a refusal: read the invoice, and never take
  payment again on it. `PaymentSheetStrings.outcomeUnknown` is what the payer is told then;
  never "try another card", because the card may already have been charged.
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

- A checkout is settled only by a return link that arrives while it is watching. The
  package listens for deep links once, as `GetPayInProvider` mounts, and drops a link that
  reaches the app with no checkout waiting for one. See [Setup](doc/setup.md) if your app
  reads links of its own.
- Nothing in flight is reported as `cancelled`. From the tap on Pay until the answer, while
  your server charges a saved card, and from the payer opening the wallet until it answers,
  the payment sheet refuses a swipe, a tap outside and Android Back, shuts every other way to
  pay, and keeps one close, which settles `outcomeUnknown`. The wallet counts as opened when
  the app goes to the background within 10 seconds of a touch on its button. A wallet that
  starts no charge within 15 seconds of the payer coming back frees the sheet again, and
  closing after it still settles `outcomeUnknown`. A wallet charge marked after its button has
  left the screen, as the payer pays another way or moves on, makes whatever the sheet reports
  next `outcomeUnknown`. A card form that fails while another payment is in flight waits for
  that payment to end before it hands the payer to the hosted checkout, and after a wallet
  that never answered it settles `outcomeUnknown` instead.
  A failed or abandoned 3-D Secure stays a step the payer can retry: PayLink's SDK asks the
  issuer before it charges.
- The one-checkout-at-a-time guard covers the payment sheet too, and the sheet lends its
  place to the one checkout `chargeSavedCard` opens for an issuer's challenge.
- What `chargeSavedCard` returns is held to the same rule as every other claim of payment:
  a `paid` naming an invoice status other than `PAID` is `notPaid`. A charge on a token
  makes its own invoice, so it is not held to `expectedInvoiceId`.
- The frame rule holds on both platforms here, not iOS only: `webview_flutter` reports
  whether the frame being navigated is the main frame on Android as well.
- Bound to `expectedInvoiceId`, the browser sheet passes over a return link that names
  another invoice, or none, and goes on waiting for its own. A link that names its invoice
  is taken even when its result cannot be read. A sheet that closes with no answer after
  passing over a link settles `outcomeUnknown`, and so does a card save.
- The payment sheet holds every result to the session's invoice when `expectedInvoiceId`
  is left out.
- A return link with a bracket or a control character in a field name is unreadable. PHP
  reads such names its own way, and the app and a server checking the link's signature must
  read the same values.
- On Android, an `intent:` link from a bank's step opens the app it names, under the same
  rules as any other link, or its web page (`browser_fallback_url`) when no app takes it.
- On iPhone, a load the web view only cancelled, as one bank redirect replaces another,
  does not interrupt the checkout.
- Checkout links and server errors are written to the log in debug builds only.
- `expectedInvoiceId: null` means "no invoice to bind to". Dart cannot tell that apart from
  a field your server left out of its JSON, so make your server always send the invoice id.
- In the app's own screen, a page that fails after the checkout has loaded is drawn over
  the checkout, which stays loaded underneath. From then on the checkout settles `notPaid`
  with `outcomeUnknown` however it goes without an answer: the payer's close, your app
  taking the screen away, or the provider going. The default texts never ask the payer to
  try again, or say that nothing was charged.
- The card page you host is generated by this package: generate it again and upload the new
  copy with every update. A copy from an older version can answer in a way the sheet no
  longer accepts, and every card payment on it then ends `outcomeUnknown`.
- The card page you host loads an SDK its own link names only from a PayLink it was
  generated for: anyone can send a payer a link to it. Name every PayLink whose wallet
  payments it takes, with `buildFieldsPageHtml(otherSdkUrls:)` or as more hosts to
  `tool/write_fields_page.dart`.
