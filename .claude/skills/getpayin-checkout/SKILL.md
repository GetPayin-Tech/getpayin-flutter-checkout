---
name: getpayin-checkout
description: Take GetPayIn payments in a Flutter app with getpayin_checkout. Apple Pay, Google Pay and card, either on the hosted checkout or on a payment sheet built from PayLink's hosted card fields. Use when adding or debugging in-app payments in Flutter, when the user mentions GetPayIn, PayLink, Apple Pay or Google Pay in Flutter, a payment WebView, a payment return deep link, GetPayInProvider, GetPayInCheckout.open, GetPayInPaymentSheet, hosted card fields, PayLinkFieldsSession, or symptoms such as a missing wallet button, HTTP 403 from a checkout link, an unmatched route after paying, or an app that never receives the payment result.
---

# GetPayIn checkout in Flutter

`getpayin_checkout` takes a GetPayIn payment inside a Flutter app and reports what
came back. It holds no secret and signs nothing.

## The rule that matters most

**The result in the app is never proof of invoice.paid* The app's return scheme is public, so
anything on the phone can open the app with
`myapp://payment-return?success=1&invoice_id=anything`.

So `status == CheckoutStatus.paid` may update the UI, but only the server's `invoice.paid`
webhook may unlock, ship, credit or grant anything. If the user asks for an app-side-only
confirmation, say why that is unsafe and offer the server check.

## Which of the two to use

| Ask                                      | Use                     | Costs                                              |
| ---------------------------------------- | ----------------------- | -------------------------------------------------- |
| "take payments", no mention of the look  | The hosted checkout     | Nothing: no origin, no hosted page, PCI SAQ A      |
| "a sheet in my app", "like Stripe"       | `GetPayInPaymentSheet`  | A registered origin, a page to host, PCI SAQ A-EP  |

Default to the hosted checkout. Only reach for the sheet when the user asks for the
checkout to look like part of their app, and tell them what it costs before building it.

## Quick start — the hosted checkout

```dart
// 1. main.dart: declare every scheme the app answers to, then mount the provider once
void main() {
  declareHostAppSchemes(const ['myapp']);
  runApp(const MyApp());
}

MaterialApp(home: GetPayInProvider(child: const ShopPage()))
```

```dart
// 2. Take a payment
final payment = await myApi.createPayment(order); // your server calls POST /v2/integration/init

final result = await GetPayInCheckout.open(
  payment.checkoutUrl,
  OpenCheckoutOptions(
    returnUrl: 'myapp://payment-return',
    expectedInvoiceId: payment.invoiceId,
    googlePayInApp: false, // true only after Google approves the app
  ),
);

if (result.status == CheckoutStatus.paid) {
  await myApi.confirmPayment(result.invoiceId);
}
```

```dart
// 3. go_router only, or payers land on an unmatched route after paying
final paymentReturn = PaymentReturnRedirect('myapp://payment-return');

GoRouter(redirect: (context, state) => paymentReturn.redirectFor(state.uri.toString()));
```

`result.status` is `paid`, `notPaid` or `cancelled`.

## Quick start — the payment sheet

```dart
final result = await GetPayInPaymentSheet.show(
  context,
  PaymentSheetConfiguration(
    session: PayLinkFieldsSession.fromInit(payment)!, // /init with mode: "fields"
    fieldsPageUrl: 'https://shop.example.com/paylink-fields.html',
    returnUrl: 'myapp://payment-return',
    expectedInvoiceId: invoiceId,
    amountLabel: r'$97.42',
    wallets: const [PaymentWallet.applePay, PaymentWallet.googlePay],
  ),
);
```

It needs hosted fields enabled for the company, a registered origin, and the page hosted
there — `dart run tool/write_fields_page.dart https://pay.getpayin.com` writes it. Read
`doc/payment-sheet.md` before building this.

## Instructions

When integrating:

1. **Install and rebuild.** `flutter pub add getpayin_checkout`, then a full
   rebuild. The web view is native code, so a hot reload is not enough.
2. **Declare the scheme natively, in both projects.** Flutter has no `app.json`: an
   `<intent-filter>` with `<data android:scheme="myapp" />` in `AndroidManifest.xml`, and
   `CFBundleURLTypes` in `Info.plist`. Then check the three places it must agree: those
   files, the integration's **Mobile App Return Scheme**, and `options.returnUrl`.
3. **Call `declareHostAppSchemes` once at startup**, listing every scheme the app answers
   to. It is what stops a page inside the checkout driving the app's own deep-link routes.
4. **Mount `GetPayInProvider` under the app's `Navigator`** — around the widget passed to
   `MaterialApp.home` is the simple place. Above one (in `MaterialApp.builder` or a router
   shell) it needs the same `navigatorKey` the app gives `MaterialApp`.
5. **Always pass `expectedInvoiceId`.** It makes the package refuse a paid link naming a
   different invoice. Never leave it null when the server returned an invoice id — in Dart
   that is indistinguishable from a field the server omitted, and it turns the check off.
6. **Keep `googlePayInApp: false`** unless the user confirms Google has approved their app.
   Setting it early gives Android payers an app screen with no Google Pay button and no
   error.
7. **Add the three `<queries>` entries** to `AndroidManifest.xml` if in-app Google Pay is
   wanted — `org.chromium.intent.action.PAY`, `IS_READY_TO_PAY`, `UPDATE_PAYMENT_DETAILS`.
   Without them the button is missing however approved the app is.
8. **Pass `checkoutUrl` in memory.** Never through a route parameter: a router decodes it
   twice and the checkout answers HTTP 403.
9. **Add the `go_router` redirect** if the project uses go_router. Check for a `GoRouter`
   to tell.
10. **Saving a card is its own call.** `/v2/integration/tokens/init` gives a
    `tokenization_url`; open it with `GetPayInCheckout.saveCard`, never with `open`. A
    verification run leaves its invoice unpaid on purpose, so `open` would report every
    successful save as `notPaid`. The token is never on the return link — it arrives with
    the `card_token.created` webhook. The payment sheet cannot save a card at all.
11. **Wire the server side**: `POST /api/v2/integration/init` to create, the `invoice.paid`
    webhook to confirm. Deliver only when the verified event says success, the invoice
    status is `PAID`, and the invoice is one that server created.

## Never do these

1. Never put the hash token, or any signing, in the app. It belongs on the server.
2. Never add a JavaScript channel or call `runJavaScript` on the checkout view, the wallet
   surface, or a web view of your own around either. WebKit turns Apple Pay off on any page
   the host app has scripted, silently.
3. Never set a user agent on the checkout web view. Google checks it and requires it to end
   with `GOOGLE_PAY_SUPPORTED`.
4. Never use the checkout's `iframe` mode in an app. It needs the integration's registered
   website as the surrounding page.
5. Never treat the return link alone as authorisation to deliver.
6. Never put the hosted-fields client token in a page URL you build by hand, and never
   serve the fields page from anywhere but the registered origin.

## Diagnosing

Match the symptom first; most of these failures are silent.

| Symptom                                    | First thing to check                                                                                       |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| Payment works, app never gets the result   | The scheme in all three places, and that the manifest/Info.plist change was rebuilt                        |
| An unmatched route after paying            | The `go_router` redirect is missing                                                                        |
| HTTP 403 from the checkout link            | `checkoutUrl` passed through a route parameter; or `(`, `)`, `'` in the order title                        |
| No Apple Pay button on iPhone              | A script was added to the page; no card in Wallet                                                          |
| No Google Pay button on Android            | The `<queries>` entries; Google has not approved the app, so use `googlePayInApp: false`; WebView < 137    |
| Blank white checkout screen                | A load failure; `onLoadError` not handled in a custom screen                                               |
| `GetPayInProviderMissingError`             | No provider mounted, or it cannot reach a `Navigator` — the message says which. iOS always uses the sheet  |
| `GetPayInSessionBusyError`                 | A double tap on Pay; guard with `GetPayInCheckout.busy`                                                    |
| A real payment came back `cancelled`       | A scheme mismatch; the webhook is the authority                                                            |
| `notPaid` naming a different invoice       | `expectedInvoiceId` refused a mismatched link; check which invoice the server created                      |
| The sheet shows an empty card box          | The page is not served from the registered origin, or hosted fields are off for the company                |
| The sheet went to the hosted checkout      | One of the six fatal fields failures; that fallback is deliberate                                          |

## API surface

| Export                                       | Purpose                                                                |
| -------------------------------------------- | ---------------------------------------------------------------------- |
| `GetPayInProvider`                           | Hosts the in-app checkout. Mount once, under the app's `Navigator`.    |
| `GetPayInCheckout.open(url, options)`        | Opens a checkout and completes with a `CheckoutResult`.                |
| `GetPayInCheckout.presentationFor(...)`      | `inApp` or `browser` for this phone, without opening anything.         |
| `GetPayInCheckout.busy`                      | True while a checkout is open.                                         |
| `GetPayInCheckoutView`                       | The checkout for a screen of your own. Handle `onLoadError`.           |
| `GetPayInPaymentSheet.show(context, config)` | The checkout as a sheet, on hosted card fields.                        |
| `PayLinkFieldsSession.fromInit(response)`    | Reads the `fields` block out of `/init`. Null when fields are off.     |
| `declareHostAppSchemes(schemes)`             | Every scheme the app answers to. Call once at startup.                 |
| `PaymentReturnRedirect`                      | Keeps a router from opening the return link as a screen.               |

Errors, all extending `GetPayInCheckoutError`: `GetPayInConfigError`,
`GetPayInProviderMissingError`, `GetPayInSessionBusyError`.

## Platform behaviour

| Platform | `googlePayInApp`  | Opens in                  | Wallets          |
| -------- | ----------------- | ------------------------- | ---------------- |
| iOS      | ignored           | The app's own screen      | Apple Pay, card  |
| Android  | `false` (default) | The phone's browser sheet | Google Pay, card |
| Android  | `true`            | The app's own screen      | Google Pay, card |

Google Pay is never offered on iPhone: Google allows it only in Safari.

## Full documentation

In the package repository: `doc/setup.md`, `doc/taking-payments.md`,
`doc/payment-sheet.md`, `doc/saving-a-card.md`, `doc/google-pay.md`, `doc/api.md`,
`doc/security.md`, `doc/troubleshooting.md`.
