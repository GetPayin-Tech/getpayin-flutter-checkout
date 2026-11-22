# The payment sheet

A payment sheet in your own app: a wallet button, the payer's saved cards, a card form, and
one pay button. It is the same GetPayIn payment as the hosted checkout, taken through
PayLink's **hosted card fields** instead of its checkout page.

Use it when you want the checkout to look like part of your app. Use the
[hosted checkout](taking-payments.md) when you want the shortest path to a working payment:
it needs no origin, no page to host and no extra PCI scope.

## What is native and what is not

| Part of the sheet                   | Drawn by                                            |
| ----------------------------------- | --------------------------------------------------- |
| The sheet, labels, rows, pay button | Flutter                                             |
| Saved cards and the card list       | Flutter, from your own backend                      |
| Card number and security code       | CyberSource, in iframes on a page you host          |
| The wallet button                   | PayLink, on an unscripted surface inside the sheet  |
| The 3-D Secure challenge            | PayLink's SDK, framed by it, over the sheet         |

The card number and security code cannot be Flutter text fields: they have to be rendered by
the gateway, which is what keeps the card out of your app. So the card box is a small web
view sized to look like one more row of the sheet. Everything around it is yours.

Every call behind the sheet goes to PayLink — the capture context, payer authentication and
the charge are PayLink endpoints, authorised by a client token that names one payment. The
app never holds your hash token and never calls a gateway.

## Before you begin

| Requirement                                             | Where                                                         |
| ------------------------------------------------------- | ------------------------------------------------------------- |
| **Hosted card fields enabled** for your company         | Off by default. Ask your GetPayIn account manager.            |
| A registered **origin** — the host that serves the page | Dashboard → **Settings → Payment Integrations**               |
| **HTTPS** on that origin                                | The card iframes and 3-D Secure will not load over HTTP.      |
| The page itself, hosted at that origin                  | [`paylink-fields.html`](paylink-fields.html) — see below      |

> **PCI scope.** The hosted checkout keeps you in **SAQ A**. Hosting the fields moves you to
> **SAQ A-EP**, because your page owns the form even though it never sees the card. Confirm
> that is acceptable to your acquirer before you build.

### Hosting the page

The page is three dozen lines and this package generates it, so the Dart side and the web
side cannot drift apart:

```sh
dart run tool/write_fields_page.dart https://pay.getpayin.com > paylink-fields.html
```

Serve that at your registered origin — `https://shop.example.com/paylink-fields.html` — and
pass the URL to the sheet. [`doc/paylink-fields.html`](paylink-fields.html) is the same file
with the host left as a placeholder, if you would rather copy it.

The origin is not a formality: it is baked into the capture context CyberSource issues and
checked on every call, so a page served from anywhere else renders nothing at all. The sheet
checks it for you and reports `origin_not_allowed` rather than showing you an empty box.

An origin that will not serve the page to a plain request — a development tunnel with an
interstitial, a staging host behind a gate — takes `fieldsPageHeaders`, which is sent with
the page and with the wallet's:

```dart
fieldsPageHeaders: const {'ngrok-skip-browser-warning': 'true'},
```

Without it the web view loads the gate's own page where the card fields should be, which
looks exactly like fields that never arrived.

## Taking a payment

Your server creates the payment with `mode: "fields"` and passes the response on:

```json
{
  "data": {
    "checkout_url": "https://pay.getpayin.com/integration/checkout?...",
    "invoice_id": 90210,
    "fields": {
      "client_token": "eyJpdiI6...",
      "sdk_url": "https://pay.getpayin.com/sdk/paylink-fields-v1.js",
      "origin": "https://shop.example.com"
    }
  }
}
```

Then the sheet is one call. `createPayment` is your server calling `/init`, and
`fromInit` answers null when hosted fields are off for the company, which is your cue to
use `checkout_url`. `savedCards` comes from your own backend:

```dart
final payment = await myApi.createPayment(order);
final session = PayLinkFieldsSession.fromInit(payment)!;

final result = await GetPayInPaymentSheet.show(
  context,
  PaymentSheetConfiguration(
    session: session,
    fieldsPageUrl: 'https://shop.example.com/paylink-fields.html',
    returnUrl: 'myapp://payment-return',
    expectedInvoiceId: session.invoiceId,
    amountLabel: r'$97.42',
    wallets: const [PaymentWallet.applePay, PaymentWallet.googlePay],
    savedCards: cards,
    chargeSavedCard: (card) => myApi.chargeSavedCard(card.id),
  ),
);

if (result.status == CheckoutStatus.paid) {
  await myApi.confirmPayment(result.invoiceId);
}
```

`result` is the same `CheckoutResult` the hosted checkout returns, read by the same rules:
only `PAID` is paid, and a charge booked against another invoice is refused. It is still a
report of what PayLink said, never proof of payment — confirm the `invoice.paid` webhook on your
server before you deliver anything.

## The billing address

The gateway renders the card number and the security code and nothing else, so the token it
mints carries **no billing address**. Without one the charge goes out against the
placeholder address configured on your company, and that is what the issuer's address check
is matched against — for a payer who is sitting right there able to answer.

Turn it on and the sheet asks:

```dart
PaymentSheetConfiguration(
  collectBillingAddress: true,
  billingCountry: 'US',
  // ...
)
```

That adds a **Name on card** row to the card box and a billing section under it: country,
street, city, a region for the countries that have one, and a postal code. The pay button
waits for a name and a street, because the gateway ignores an address carrying less than
that and the payer would never learn why their bank refused.

Three things are worth knowing before you switch it on:

- **Your company has to have the billing fields enabled.** Without the flag PayLink ignores
  what the sheet sends and keeps using the placeholders.
- **A region is only read for the United States and Canada.** The sheet asks for one only
  there, and calls it a state or a province to suit.
- **Email and phone are not part of it.** They keep their existing source, which is the
  payment your server created.

## Wallets

Name both; the sheet shows the one that belongs on the phone — Apple Pay on iOS, Google Pay
on Android. Only one is ever offered, because a charge is booked under the first wallet its
capture context carried, not the one the payer picked.

The wallet button is PayLink's, rendered inside a web view that this package **never
scripts**: WebKit turns Apple Pay off on any page the host app has added scripts to, so the
one surface that shows a wallet is the one surface that is left alone. It answers the only
way an unscripted page can — by navigating to your return link, which the sheet reads exactly
as the hosted checkout does.

| Wallet     | Available when                                                                   |
| ---------- | -------------------------------------------------------------------------------- |
| Google Pay | Your company sells Google Pay. Nothing per-domain.                               |
| Apple Pay  | Your company sells it **and** GetPayIn has verified your origin with Apple.      |

Apple fetches an association file from the domain showing the button, and that domain is
yours. Ask your account manager to start that; until it is done the button is quietly
dropped and the card form is unaffected.

## Saved cards

Hosted fields cannot save a card — PayLink refuses `tokenize` on a fields payment, because
the consent wording would be on a form it does not own. So saved cards work like this:

1. A card is vaulted by a payment run through the **hosted checkout** with `tokenize: true`,
   or through `/v2/integration/tokens/init`.
2. Your server keeps the token it gets back against your own customer.
3. The sheet shows what you pass in `savedCards` and tells you which one the payer picked.
4. `chargeSavedCard` is **your server's** call to `/v2/integration/tokens/charge`, signed
   with your hash token. The app never holds it.

## When the fields cannot run

Six failures mean the payer cannot pay here at all: `fields_unavailable`,
`fields_unsupported`, `session_invalid`, `origin_not_allowed`, `library_unavailable` and
`payments_paused`. The sheet closes and sends the payer to `checkout_url` instead, which is
the behaviour you want and why `fallBackToHostedCheckout` defaults to on. The hosted checkout
needs no origin and no page, so it always works.

Turn it off and the sheet settles with `CheckoutStatus.notPaid` and
`CheckoutResultCode.checkoutUnavailable` instead — nothing was charged and nothing was
declined, so do not show the payer a decline.

Everything else — a declined card, a failed or abandoned 3-D Secure, a bad expiry — keeps the
sheet open with the reason, and the payer can try again on the same form.

## Styling it

`PaymentSheetStyle` is handed to both sides: Flutter draws the sheet with it, and the page
is handed the same few values as CSS custom properties, so the card box cannot drift away
from the rows above it. `PaymentSheetStrings` is every word the sheet says.

The card networks' marks are trademarks with their own artwork rules, so this package ships
none: it writes the brand on a neutral chip. Pass your own widgets when you have the marks
your acquirer approved.

## Building your own sheet

The pieces the sheet is made of are exported, so a different layout does not mean starting
over: `CardFieldsController` owns the card box and reports `FieldsEvent`s,
`WalletSurface` is the wallet button, `resultFromPayment` turns PayLink's answer into a
`CheckoutResult` by the same rules, and `buildFieldsPageHtml` writes the page.

## The upstream contract

This guide covers the Flutter side. PayLink's own **Hosted Card Fields — Integration
Guide**, served at `/docs/payment_integration/HOSTED_FIELDS_GUIDE.md` on your PayLink host,
is the authority on the API behind it: the `/init` call, the `fields/*` endpoints, the error
codes, the CSP a web page needs, and what the client token can and cannot do. When the two
disagree, it wins.

## Next

[API reference](api.md) · [Security model](security.md) · [Troubleshooting](troubleshooting.md)
