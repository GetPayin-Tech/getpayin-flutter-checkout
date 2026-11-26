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

The page is three dozen lines and this package generates it. Generate it again and upload
the new copy with every update of this package: the sheet and the page answer each other,
and a copy made by an older version can answer in a way the sheet no longer accepts, so
every card payment on it ends `CheckoutResultCode.outcomeUnknown`.

```sh
dart run tool/write_fields_page.dart https://pay.getpayin.com > paylink-fields.html
```

Serve that at your registered origin — `https://shop.example.com/paylink-fields.html` — and
pass the URL to the sheet. [`doc/paylink-fields.html`](paylink-fields.html) is the same file
with the host left as a placeholder, if you would rather copy it.

The host you generate it with is the one it falls back on, not the only one it can use: the
page asks `/init` which PayLink this payment belongs to and loads the SDK from there. One
page serves staging and production, so long as your Content Security Policy allows script
from both. Get this wrong with a page pinned to one of them and the error names the *other*
environment, which is a long way to the answer.

The wallet button is the exception, because it reads its SDK address from the page's own
link and anyone can send a payer a link to your page. It loads only an SDK from a PayLink
the page was generated for, so name them all, the main one first:

```sh
dart run tool/write_fields_page.dart https://pay.getpayin.com https://staging.example.com > paylink-fields.html
```

The origin is not a formality: it is baked into the capture context CyberSource issues and
checked on every call, so a page served from anywhere else renders nothing at all. The sheet
checks it for you and reports `origin_not_allowed` rather than showing you an empty box, and
it keeps checking afterwards: the card box loads your page and no other, whatever the page
asks for next. What the page frames — the card fields, and the issuer's 3-D Secure step — is
unaffected.

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
final session = PayLinkFieldsSession.fromInit(payment.data);

if (session == null) {
  return GetPayInCheckout.open(
    payment.checkoutUrl,
    OpenCheckoutOptions(
      returnUrl: 'myapp://payment-return',
      expectedInvoiceId: payment.invoiceId,
    ),
  );
}

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

`expectedInvoiceId` can be left out: the sheet then holds results to the invoice the session
names, which is the same one.

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

## Keeping the card

A fields payment can vault the payer's card as well as charging it, off the same
authorization — no second hold and no second visit. It needs one thing beyond
`tokenize: true`, and the reason is worth understanding before you build it.

The card networks require explicit cardholder agreement before a card is kept on file, and
PayLink has to be able to evidence what was agreed to. On its own checkout it renders that
box itself. On your page there is nothing of PayLink's to show, so **you send the exact
wording you showed**, and that is what is stored and relied on in a dispute:

```json
{
  "mode": "fields",
  "tokenize": true,
  "tokenization_consent_text": "Save my card for future payments."
}
```

Leave it out and `/init` refuses with `422 tokenize_consent_required`, naming the field and
pointing you at `checkout_url` instead. Like `tokenize`, the field sits outside the
signature, so adopting it changes nothing about the string you sign.

**Ask before you create the payment, not on the sheet.** PayLink is told the payer agreed at
`/init`, which happens before the sheet opens — so the tick belongs on your own order
screen, and the wording you show there is the wording you send. Collecting it afterwards
would be asserting something you had already asserted.

Show the same string in both places from one constant. Two copies is how an integrator ends
up unable to say what was actually on screen:

```dart
const String cardSaveConsent = 'Save my card for future payments.';
```

The token arrives on the `card_token.created` webhook once the payment is approved, and a
run that ends without one raises `card_token.failed` rather than leaving you waiting. Charge
it later with `/v2/integration/tokens/charge`, which never leaves your app.

`PaymentSheetConfiguration.keepTheCard` draws a consent row inside the card box instead,
rendered by PayLink's own SDK. That is the stronger arrangement — the wording is PayLink's
and the tick is captured first-hand — but it needs an SDK release that carries it, so until
then the order-screen consent above is the path that works.

## Wallets

Name both; the sheet shows the one that belongs on the phone — Apple Pay on iOS, Google Pay
on Android. Only one is ever offered, because a charge is booked under the first wallet its
capture context carried, not the one the payer picked.

The wallet button is PayLink's, rendered inside a web view that this package **never
scripts**: WebKit turns Apple Pay off on any page the host app has added scripts to, so the
one surface that shows a wallet is the one surface that is left alone. It answers the only
way an unscripted page can — by navigating to your return link, which the sheet reads exactly
as the hosted checkout does. The charge starts a few seconds after the wallet's own sheet
closes, and the page cannot see that sheet at all, so the sheet holds still from the moment
the wallet puts the app in the background: the app leaving within 10 seconds of a touch on
the wallet button. The page marks its own address once the charge is out, and the sheet
holds, on the wallet's screen, until the answer. A payer who comes back without paying leaves
nothing on the page to say so: if no charge starts within 15 seconds of the app being back,
the sheet lets the payer use it again. A wallet charge marked later still, after its button
has left the screen as the payer pays another way or moves on to the card form, has no button
left to answer on: from then on the sheet reports the payment as `outcomeUnknown`, so your
server checks what went through.

| Wallet     | Available when                                                                   |
| ---------- | -------------------------------------------------------------------------------- |
| Google Pay | Your company sells Google Pay. Nothing per-domain.                               |
| Apple Pay  | Your company sells it **and** GetPayIn has verified your origin with Apple.      |

Apple fetches an association file from the domain showing the button, and that domain is
yours. Ask your account manager to start that; until it is done the button is quietly
dropped and the card form is unaffected.

## Saved cards

A token never reaches the app, in either direction: the sheet is told which card the payer
picked, and your server is the only thing that can charge it. So saved cards work like this:

1. A card is vaulted by a payment carrying `tokenize: true` — the sheet's own, as
   [Keeping the card](#keeping-the-card) describes, or a hosted one — or by a
   verification run through `/v2/integration/tokens/init`, which the sheet cannot take.
2. Your server keeps the token it gets back against your own customer.
3. The sheet shows what you pass in `savedCards` and tells you which one the payer picked.
4. `chargeSavedCard` is **your server's** call to `/v2/integration/tokens/charge`, signed
   with your hash token. The app never holds it.
5. What `chargeSavedCard` returns is a claim of payment, held to the same rule as every
   other: a `paid` naming an `invoiceStatus` other than `PAID` is reported as `notPaid`.
   Always pass `invoiceStatus`: a `paid` without one is taken as it stands. A charge on a
   token makes its own invoice, so the sheet does not hold it to `expectedInvoiceId`.
   Return that invoice's `invoice_id` and `paid_status` as `invoiceId` and `invoiceStatus`.
   Past that rule the sheet takes the result as your server reports it: your server
   confirms the charge.
6. PayLink's answer says how the charge went. A `201` with `success: true` is a charge, a
   `202` is the issuer's challenge, and a `422` with `success: false` is a decline, which
   you return as `notPaid` with no code so the payer can try again. Anything else may have
   come after the card was charged, because PayLink records the payment after the gateway
   answers: a server error, a timeout, an answer you cannot read. Return
   `CheckoutResultCode.outcomeUnknown` for it, never a decline.
7. When the issuer wants to challenge the payer, your server gets back what the challenge
   needs. Open it with `GetPayInCheckout.open` inside `chargeSavedCard` and return what it
   settles with: the sheet holds the one-checkout-at-a-time guard, and lends its place to
   that one checkout. Pass the `202`'s `invoice_id` as `expectedInvoiceId`: the challenge
   answers on a return link, and that is what ties the link to this charge. The return link
   your server sends at the end of the challenge carries that same `invoice_id`, even when
   it cannot say how the charge ended: bound to it, the browser sheet on Android waits past
   a link that names another invoice, or none. The example
   app does exactly this. A payer who closes the challenge may have answered the issuer
   first, so a `cancelled` from it is reported as `CheckoutResultCode.outcomeUnknown`.
8. A server error from your own server after the charge left is not a decline: return
   `CheckoutResultCode.outcomeUnknown`, never a result that invites another card. Throwing
   does the same.

## When the fields cannot run

These failures mean the payer cannot pay here at all: `fields_unavailable`,
`fields_unsupported`, `session_invalid`, `origin_not_allowed`, `integration_inactive`,
`payment_not_found`, `library_unavailable`, `payments_paused`, `not_payable`, `expired`, and
any code this package does not know. The sheet closes and sends the payer to `checkout_url`
instead, which is the behaviour you want and why `fallBackToHostedCheckout` defaults to on.
The hosted checkout needs no origin and no page, so it always works, and for a payment that
is over it says why in PayLink's own words. A page sent away from your origin before its
fields are live counts as `origin_not_allowed`. The card form loads while the payer is still
on the first screen, so one of these can arrive while a wallet or saved-card payment is in
flight: the sheet then waits for that payment to end, and hands over only if it ended without
a payment. After a wallet the payer opened that never answered, it settles
`CheckoutResultCode.outcomeUnknown` instead, because that wallet can still charge.

Turn it off and the sheet settles with `CheckoutStatus.notPaid` and
`CheckoutResultCode.checkoutUnavailable` instead — nothing was charged and nothing was
declined, so do not show the payer a decline.

`already_paid` is the exception. PayLink sends it the moment the fields open on an invoice
that is paid, which may be this payer's own payment from a minute ago, so the sheet never
sends them to pay again: it settles with `CheckoutResultCode.outcomeUnknown`, with the
fallback on or off. Read the invoice on your server.

Everything else — a declined card, a failed or abandoned 3-D Secure, a bad expiry — keeps the
sheet open with the reason, and the payer can try again on the same form. PayLink's SDK asks
the issuer before it charges, so a failed 3-D Secure never follows a charge.

From the tap on Pay until the answer, nothing closes behind the payer: a swipe, a tap above
the sheet and Android Back are all refused, the other ways to pay on the sheet are shut, and
the card screen's back arrow becomes a close. Once the charge itself is out, nothing falls
back either; before that, a failure that means the fields cannot run still hands the payer
over, because nothing has been charged yet. The same holds while your
server charges a saved card, and from the payer opening the wallet until its answer, or until
15 seconds after they are back with no charge started. Leaving the app without touching the
wallet first — a notification, a call — holds nothing, and closing then is still `cancelled`.
The close is always there, the issuer's challenge included, because a charge can hang, and
closing then settles with `CheckoutResultCode.outcomeUnknown`, never `cancelled`. So does
closing after a wallet the payer opened that never answered, and an answer that never
arrives: the page died, the network went, your own `chargeSavedCard` threw after the call had
left. That is not a decline and not a cancellation: read the invoice on your server, and never
take payment for the order again on it.

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

Keep the sheet's rule about leaving. A card attempt is in flight from the tap on Pay until
its answer: `CardFieldsController.isCharging` and `isAuthenticating` cover the issuer's
check, and `chargeStarted` the charge itself. A wallet charge is in flight from the app going
to the background right after a touch on `WalletSurface` until `WalletSurface.onComplete`;
`WalletSurface.onCharging` says the charge itself is out. While any of them is, a payer who
leaves has not cancelled anything; report the payment as one nobody can confirm. Keep
`WalletSurface` on screen until `onComplete`: one that leaves ends its page and calls neither
`onComplete` nor `onCharging` again. When its page marked its charge just before,
`onChargingAfterLeaving` says so. That charge is out with no answer to come, even with a new
surface in its place, so report the payment as one nobody can confirm then too. It can run
after your own widget is gone, so check `mounted` in it.

## The upstream contract

This guide covers the Flutter side. PayLink's own **Hosted Card Fields — Integration
Guide**, served at `/docs/payment_integration/HOSTED_FIELDS_GUIDE.md` on your PayLink host,
is the authority on the API behind it: the `/init` call, the `fields/*` endpoints, the error
codes, the CSP a web page needs, and what the client token can and cannot do. When the two
disagree, it wins.

## Next

[API reference](api.md) · [Security model](security.md) · [Troubleshooting](troubleshooting.md)
