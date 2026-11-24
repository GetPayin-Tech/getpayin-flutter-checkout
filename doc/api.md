# API reference

Everything the package exports. The doc comments ship with it, so your editor has all of
this too.

## `GetPayInCheckout.open(checkoutUrl, options)`

```dart
static Future<CheckoutResult> open(String checkoutUrl, OpenCheckoutOptions options)
```

Presents the checkout and completes once it ends. `checkoutUrl` is the `checkout_url` your
server received from `POST /api/integration/init`; it must be an `http(s)` URL and must be
passed in memory rather than through a route parameter.

Every failure arrives as a failed future, so one `catch` covers them all.

### `OpenCheckoutOptions`

| Option              | Type                     | Default             | What it does                                                                                                                                                                                   |
| ------------------- | ------------------------ | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `returnUrl`         | `String`                 | required            | The link the checkout returns to. Must match the integration's Mobile App Return Scheme.                                                                                                       |
| `expectedInvoiceId` | `Object?`                | `null`              | The invoice your server created this checkout for: a `String` or an `int`. Compared as trimmed text, leading zeros ignored. A return link naming a different invoice is reported as `notPaid`. |
| `googlePayInApp`    | `bool`                   | `false`             | Draw the checkout in the app's own screen on Android. Set it only after Google approves your app. Ignored on iOS.                                                                              |
| `ownSchemes`        | `List<String>`           | `const []`          | Extra schemes this checkout should refuse, on top of `declareHostAppSchemes`.                                                                                                                  |
| `title`             | `String?`                | `'Secure checkout'` | Title in the in-app screen's top bar.                                                                                                                                                          |
| `closeLabel`        | `String?`                | `'Close'`           | Label of the top bar's close button, in your app's language. Also what a screen reader announces when set.                                                                                     |
| `loadErrorMessage`  | `String?`                | English text        | Shown to the payer when the checkout page cannot be loaded.                                                                                                                                    |
| `linkErrorMessage`  | `String?`                | English text        | Shown to the payer when the phone cannot open a link the checkout needed, such as a bank app for 3-D Secure that is not installed.                                                             |
| `headerShown`       | `bool`                   | `true`              | Show the top bar, which is the payer's only way to close the checkout. The bar is shown anyway if the checkout fails to load, so a failure always has a way out.                               |
| `presentation`      | `CheckoutPresentation?`  | `null`              | Overrides the platform rule. For tests and for diagnosing a build.                                                                                                                             |

`expectedInvoiceId` is typed `Object?` because the two sides disagree: init returns the
invoice id as a JSON number and the return link carries it as text. A non-blank `String` or
a whole number is accepted; `''`, a `bool`, a `Map`, a `List`, and a fractional or
non-finite number are refused with `GetPayInConfigError`. `null` means "no invoice to bind
to" and turns the check off, which is also what a field your server left out of its JSON
looks like — Dart cannot tell those apart.

## `GetPayInCheckout.saveCard(tokenizationUrl, options)`

```dart
static Future<CardSaveResult> saveCard(
  String tokenizationUrl,
  OpenCheckoutOptions options,
)
```

Opens a hosted card tokenization — the `tokenization_url` from
`POST /v2/integration/tokens/init` — and completes once the payer has finished. Presented
exactly as a checkout is, and refusing exactly what `open` refuses, but read as a card save:
a verification run leaves its invoice unpaid on purpose, which the payment rules would call
a failure.

The token is not in the result and never reaches the app. It arrives on your server with the
`card_token.created` webhook. See [Saving a card](saving-a-card.md).

### `CardSaveResult`

```dart
class CardSaveResult {
  /// `saved`, `notSaved` or `cancelled`.
  final CardSaveStatus status;

  /// The verification invoice the run went against.
  final String? invoiceId;

  /// `AUTHORIZED`, `VOIDED` or `CAPTURED`. Never `PAID`.
  final String? verificationStatus;

  /// `unreadableReturnLink` or `wrongInvoice`, and null for a card simply refused.
  final CheckoutResultCode? code;

  final String? message;
  final String? returnUrl;

  bool get isSaved;
}
```

## `invoiceIdInCheckoutUrl(url)`

```dart
String? invoiceIdInCheckoutUrl(String url)
```

The invoice id a hosted `checkout_url` or `tokenization_url` names, so a run can pass
`expectedInvoiceId` and refuse a return link that belongs to another one.

## `GetPayInCheckout.presentationFor(...)`

```dart
static CheckoutPresentation presentationFor({
  bool googlePayInApp = false,
  CheckoutPresentation? override,
})
```

Returns `CheckoutPresentation.inApp` or `.browser` for this phone and these options without
opening anything. Useful on a diagnostic screen.

## `GetPayInCheckout.busy`

```dart
static bool get busy
```

True while a checkout is open. Guard your Pay button with it to avoid
`GetPayInSessionBusyError` on a double tap.

## `declareHostAppSchemes(schemes)` and `hostAppSchemes()`

```dart
void declareHostAppSchemes(Iterable<String> schemes)
List<String> hostAppSchemes()
```

Declares every URL scheme your app answers to, once at startup, so the checkout can refuse
them all whenever a link is not the return link. `'myapp'`, `'myapp://'` and `'MyApp:'` are
all read as the same scheme. See [Setup](setup.md#declaring-every-scheme-your-app-answers-to).

## `GetPayInProvider`

```dart
GetPayInProvider({Widget? child, GlobalKey<NavigatorState>? navigatorKey})
```

Hosts the in-app checkout screen. Mount it once, under your app and above the screens that
take payments. `open()` needs it to present an in-app checkout.

It presents a full-screen route on your app's own `Navigator`, so the system back button
closes the checkout. Pass `navigatorKey` when the provider sits above the navigator, as in
`MaterialApp.builder` or a router shell.

## `GetPayInCheckoutView`

```dart
GetPayInCheckoutView({
  required String checkoutUrl,
  required String returnUrl,
  required void Function(CheckoutResult result) onComplete,
  Object? expectedInvoiceId,
  List<String> ownSchemes = const [],
  String? loadErrorMessage,
  String? linkErrorMessage,
  CheckoutLoadErrorCallback? onLoadError,
})
```

The checkout itself, for a screen of your own. `onComplete` fires once per checkout;
changing `checkoutUrl` starts a new one. Handle `onLoadError`: it also reports an unusable
`checkoutUrl`, `returnUrl` or `expectedInvoiceId`, which is passed to you rather than
thrown, so a bad value from your server does not take the screen down.

`onLoadError`'s first argument is for the payer, already in your app's language. The second
is the developer-facing cause when there is one, naming the option and the value it got:
log it, and never put it on a payment screen.

Do not register a JavaScript channel on this view, call `runJavaScript` on it, or add
scripts to a web view of your own around it.

## `GetPayInPaymentSheet.show(context, configuration)`

```dart
static Future<CheckoutResult> show(
  BuildContext context,
  PaymentSheetConfiguration configuration,
)
```

Presents the checkout as a payment sheet in your app and completes once the payment ends.
See [The payment sheet](payment-sheet.md), which covers what it needs before it can run.

### `PaymentSheetConfiguration`

| Option                     | Type                                              | Default    | What it does                                                                               |
| -------------------------- | ------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------ |
| `session`                  | `PayLinkFieldsSession`                            | required   | The payment, from your server's `/init` with `mode: "fields"`.                             |
| `fieldsPageUrl`            | `String`                                          | required   | The page you host at the integration's registered origin.                                  |
| `returnUrl`                | `String`                                          | required   | The link a wallet charge comes back to, and the one the hosted fallback uses.              |
| `fieldsPageHeaders`        | `Map<String, String>`                             | `{}`       | Headers the page is asked for with, for an origin that will not serve it without.          |
| `collectBillingAddress`    | `bool`                                            | `false`    | Ask the payer for the address the card is billed to, and the name it is in.                |
| `keepTheCard`              | `bool`                                            | `false`    | Ask the payer to keep the card for next time. PayLink's SDK draws the agreement.           |
| `successPause`             | `Duration`                                        | `1200ms`   | How long the sheet says the payment went through before it closes.                         |
| `onHandover`               | `void Function(FieldsError)?`                     | `null`     | Called with the reason when the sheet gives up and opens the hosted checkout.              |
| `onDiagnostic`             | `void Function(String)?`                          | `null`     | A line for everything the card box reports. Says what happened, never what was typed.      |
| `billingCountries`         | `List<BillingCountry>`                            | all        | The countries the billing form offers. Narrow it, or translate it.                         |
| `billingCountry`           | `String`                                          | `'EG'`     | The country that form starts on, as an ISO 3166-1 alpha-2 code.                            |
| `expectedInvoiceId`        | `Object?`                                         | `null`     | The invoice this payment is for, so a charge booked against another is refused.            |
| `amountLabel`              | `String?`                                         | `null`     | What the pay button says until the gateway has priced the payment.                         |
| `wallets`                  | `List<PaymentWallet>`                             | `[]`       | The wallets to offer. One is shown: the one that belongs on this platform.                 |
| `savedCards`               | `List<SavedCard>`                                 | `[]`       | The payer's vaulted cards, from your own backend.                                          |
| `chargeSavedCard`          | `Future<CheckoutResult> Function(SavedCard)?`     | `null`     | Charges a vaulted card. Your server's call, since it is signed with your hash token.       |
| `ownSchemes`               | `List<String>`                                    | `[]`       | Extra schemes the wallet surface should refuse, on top of `declareHostAppSchemes`.         |
| `style`                    | `PaymentSheetStyle`                               | Stripe-ish | How the sheet is drawn, on both sides of the card box.                                     |
| `strings`                  | `PaymentSheetStrings`                             | English    | Every word the sheet says.                                                                 |
| `fallBackToHostedCheckout` | `bool`                                            | `true`     | Send the payer to `checkout_url` when the fields cannot take this payment.                 |

## `PayLinkFieldsSession.fromInit(response)`

```dart
static PayLinkFieldsSession? fromInit(Map<String, Object?> response)
```

Reads the session out of what `/init` answered, taking either the whole envelope or its
`data` block. Null when the response carries no `fields` block — which is what a company
without hosted fields gets — so fall back to `checkout_url`.

## `buildFieldsPageHtml(sdkUrl:)`

```dart
String buildFieldsPageHtml({required String sdkUrl, String channel = fieldsChannelName})
```

Writes the page you host at your registered origin. `dart run tool/write_fields_page.dart`
prints it, and [`doc/paylink-fields.html`](paylink-fields.html) is a copy of it.

## `PaymentReturnRedirect`

```dart
PaymentReturnRedirect(String returnUrl, {String initialPath = '/'})

bool matches(String path)
String? redirectFor(String path)
```

Recognises the return link arriving as a route, so your router does not open it as a screen.
`redirectFor` returns `initialPath` for the return link and `null` for everything else,
which is what `go_router`'s `redirect` expects. Matching is on whole path segments.

## Types

### `CheckoutResult`

```dart
class CheckoutResult {
  final CheckoutStatus status;
  final String? invoiceId;
  final String? invoiceStatus;
  final CheckoutResultCode? code;
  final String? message;
  final String? returnUrl;

  bool get isPaid;
}
```

A report of what the return link said, never proof of payment. Values compare by field, so
two results with the same contents are equal.

`invoiceStatus` is the invoice state the link reported, as GetPayIn wrote it: `PAID`,
`UNPAID`, `PARTIALLY_PAID`, `AUTHORIZED`. Only `PAID` is reported as `paid`.

### `CheckoutStatus`

```dart
enum CheckoutStatus { paid, notPaid, cancelled }
```

Each value carries a `wireName` (`'paid'`, `'not_paid'`, `'cancelled'`), which is the form
GetPayIn's own APIs and the other SDKs use — for logs and payloads, not for branching.

### `CheckoutResultCode`

```dart
enum CheckoutResultCode { unreadableReturnLink, wrongInvoice, unexpectedInvoiceStatus }
```

Why a checkout was not reported as paid, when the reason is worth acting on. `message` is
text for the payer and changes with your app's language; this is the stable value to branch
on, and the key to look a message of your own up by.

| Code                      | What happened                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `unreadableReturnLink`    | The link's own fields could not be read. Alert on it: the backend and this reader disagree about the shape. |
| `wrongInvoice`            | The link named an invoice other than the one the checkout was opened for.                                   |
| `unexpectedInvoiceStatus` | The link reported `success=1` with an `invoice_status` other than `PAID`.                                   |

A genuine decline carries no code at all, which is how it is told apart from a link that
could not be read. The payer may well have paid in all three cases, so none of them is a
reason to ask for payment again before the invoice has been checked on your server.

### `CheckoutPresentation`

```dart
enum CheckoutPresentation { inApp, browser }
```

### Other exported types

`CheckoutOptions`, `CheckoutPresenter`, `CheckoutRequest`, `CheckoutLoadErrorCallback`,
`NavigationContext`, `NavigationVerdict`, `NavigationRequestInfo`,
`CheckoutWebViewSettings`.

### The default texts

`defaultLoadErrorMessage`, `defaultLinkErrorMessage`, `defaultCheckoutTitle`,
`defaultCloseLabel`, `defaultCloseAccessibilityLabel`, `closedByPayerMessage` and
`closedByUnmountMessage` are exported so you can translate against them, or recognise the
message a cancelled result carries.

## Errors

All extend `GetPayInCheckoutError`, which implements `Exception` and carries a `message`.

| Error                          | When                                                                                                                 |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `GetPayInConfigError`          | `checkoutUrl` is not an `http(s)` URL, `returnUrl` has no scheme, or `expectedInvoiceId` cannot be an invoice id.    |
| `GetPayInProviderMissingError` | An in-app checkout with no `GetPayInProvider` mounted, or one that cannot reach a `Navigator`.                       |
| `GetPayInSessionBusyError`     | Another checkout is still open.                                                                                      |

## Lower-level exports

These are the package's own decision-making, exported because they are useful for tests and
diagnostics. You do not need them for a normal integration.

| Export                                                        | What it does                                                                                                 |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `readReturnClaim(url)`                                        | What a return link says, before any rule about what it is allowed to mean.                                   |
| `readCheckoutResult(url)`                                     | Turns GetPayIn's return link (`success`, `invoice_id`, `invoice_status`, `message`) into a `CheckoutResult`. |
| `readCardSave(url, {expectedInvoiceId})`                      | The same link, read as a card save rather than as a payment.                                                 |
| `cardSaveFromCheckout(result, {expectedInvoiceId})`           | Reads a card save out of a `CheckoutResult` the package already produced.                                    |
| `resolveReturn(url, {expectedInvoiceId})`                     | The same, bound to an invoice. Both presentations use this.                                                  |
| `matchesReturnUrl(url, returnUrl)`                            | True when `url` is the return link, whatever its query.                                                      |
| `cancelledResult([message])`                                  | The result a payer who closed the checkout gets.                                                             |
| `resolvePresentation({platform, googlePayInApp, override})`   | The platform rule, as a pure function over a platform name.                                                  |
| `classifyNavigation(url, context)`                            | A `NavigationVerdict` for one navigation.                                                                    |
| `CheckoutNavigationHandler`                                   | The web view's navigation decision, for embedding the checkout yourself.                                     |
| `buildCheckoutWebViewSettings(platform)`                      | The web view settings the wallets need.                                                                      |

### Embedding the checkout in a web view of your own

`classifyNavigation` and `CheckoutNavigationHandler` both need the full picture of what the
app answers to, so neither has a default for it:

```dart
final handler = CheckoutNavigationHandler(
  returnUrl: 'myapp://payment-return',
  expectedInvoiceId: invoiceId,
  ownSchemes: hostAppSchemes(),
  onComplete: (result) => finish(result),
  onExternal: (url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
);

NavigationDelegate(
  onNavigationRequest: (request) {
    final allowed = handler(
      NavigationRequestInfo(url: request.url, isTopFrame: request.isMainFrame),
    );

    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  },
);
```

One handler belongs to one checkout: it completes at most once, so build a new one when the
checkout changes and keep the old one across rebuilds.
