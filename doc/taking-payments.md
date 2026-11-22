# Taking payments

## The flow

```text
your app  ──▶  your server  ──▶  GetPayIn        creates the payment, returns checkout_url
your app  ◀──  your server                       checkout_url + invoiceId
your app  ──▶  this package                      opens the checkout, payer pays
your app  ◀──  this package                      CheckoutResult
your app  ──▶  your server                       confirm before you deliver anything
          ◀──  GetPayIn                          invoice.paid webhook, the real answer
```

Your server is the only place that knows whether a payment happened. The app's result is a
report of what the return link said.

## Opening a checkout

```dart
Future<void> pay(Order order) async {
  final payment = await myApi.createPayment(order);

  final result = await GetPayInCheckout.open(
    payment.checkoutUrl,
    OpenCheckoutOptions(
      returnUrl: 'myapp://payment-return',
      expectedInvoiceId: payment.invoiceId,
      googlePayInApp: false,
    ),
  );

  switch (result.status) {
    case CheckoutStatus.paid:
      await myApi.confirmPayment(result.invoiceId);
    case CheckoutStatus.notPaid:
      if (result.code != null) {
        await myApi.checkInvoice(payment.invoiceId);
      }
      showMessage(result.message ?? 'The payment did not go through.');
    case CheckoutStatus.cancelled:
      break;
  }
}
```

A `code` means the package refused the link rather than the card being declined. The payer
may well have paid, so check the invoice instead of asking them to pay again.

Pass `checkoutUrl` **in memory**. A route parameter decodes it twice and the checkout
answers HTTP 403.

## The result

| `status`    | What it means                                                                     | What to do                            |
| ----------- | --------------------------------------------------------------------------------- | ------------------------------------- |
| `paid`      | The return link said the payment went through.                                    | Confirm on your server, then deliver. |
| `notPaid`   | Declined, failed, or a return link that could not be trusted. `message` says why. | Show `message`. See `code` below.     |
| `cancelled` | The payer closed the checkout or the browser sheet.                               | Nothing. Leave the cart as it was.    |

`cancelled` only ever comes from the payer closing the screen. A hosted checkout the payer
abandons and returns from reports `notPaid`.

`invoiceId` is present when the return link carried one. `invoiceStatus` is the invoice
state the link reported (`PAID`, `UNPAID`, `PARTIALLY_PAID`, `AUTHORIZED`), and only `PAID`
is reported as `paid`. `returnUrl` is the raw link the result came from, which is useful in
a bug report. `result.isPaid` is shorthand for the status check.

### `code` on a `notPaid`

A `notPaid` the package decided for itself carries a `code`; a genuine decline carries
none. It is the stable value to branch on and to look a message of your own up by, where
`message` is text for the payer and changes with your app's language.

| `code`                                        | What happened                                           | What to do                                                           |
| --------------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------- |
| `null`                                        | The checkout declined or failed the payment.            | Show `message`. Offer a retry.                                       |
| `CheckoutResultCode.unreadableReturnLink`     | The link's own fields could not be read.                | Check the invoice on your server. Alert on this one; it is a bug.    |
| `CheckoutResultCode.wrongInvoice`             | The link named another invoice.                         | Check the invoice on your server. Do not retry blindly.              |
| `CheckoutResultCode.unexpectedInvoiceStatus`  | `success=1` with an `invoice_status` other than `PAID`. | Check the invoice on your server. An authorised invoice is not paid. |

The payer may well have paid in all three of those, so none of them is a reason to ask for
payment again before the invoice has been checked on your server.

## Confirming it

`CheckoutStatus.paid` is a claim, not an authorisation. Your return scheme is public: it is
in your `Info.plist` and your `AndroidManifest.xml`, so any web page, message, QR code or
other app on the phone can open your app with
`myapp://payment-return?success=1&invoice_id=anything`.

Confirm with the `invoice.paid` webhook on your server before you deliver. Deliver only
when the verified webhook also says `success` and `PAID`, and the invoice is one you
created.

See [the security model](security.md) for what the package does on its side.

## Errors

Every failure arrives as a failed future, so one `catch` covers them all:

```dart
try {
  final result = await GetPayInCheckout.open(checkoutUrl, options);
} on GetPayInSessionBusyError {
  return;
}
```

| Error                          | Cause                                                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `GetPayInConfigError`          | `checkoutUrl` is not an http(s) URL, `returnUrl` has no scheme, or `expectedInvoiceId` cannot be an invoice id.    |
| `GetPayInProviderMissingError` | An in-app checkout with no `GetPayInProvider` mounted, or one that cannot reach a `Navigator`.                     |
| `GetPayInSessionBusyError`     | Another checkout is still open. Usually a double tap.                                                              |

That one is a double tap on Pay, which is worth ignoring rather than reporting. It is the
common one. Either guard the button with
`GetPayInCheckout.busy`, or catch and ignore `GetPayInSessionBusyError` as above.

One mistake the package cannot catch: `expectedInvoiceId: null` means "no invoice to bind
to", and a field your server left out of its JSON arrives as exactly that. Dart cannot tell
the two apart, so make your server always send the invoice id, or check for it before you
call `open()`. Anything else unusable — `''`, a `bool`, a `Map`, a fractional number — is
refused with `GetPayInConfigError` rather than quietly turning the check off.

## Retrying

After a `notPaid`, create a **new** payment on your server and open the new
`checkoutUrl`. Do not reopen the old one: a checkout link is for one attempt, and its
invoice is already in a terminal state.

## Saving the card for next time

A payment can vault the card as it goes — `POST /v2/integration/init` with
`tokenize: true` — and a card can be vaulted on its own, with no sale, through
`/v2/integration/tokens/init` and `GetPayInCheckout.saveCard`. A save is not a payment and
is not read like one, so it has its own guide: [Saving a card](saving-a-card.md).

## Where the checkout is drawn

You do not choose this per call; the platform does, with one setting for Android:

| Platform | `googlePayInApp`  | Where it opens            |
| -------- | ----------------- | ------------------------- |
| iOS      | anything          | Your app's own screen     |
| Android  | `false` (default) | The phone's browser sheet |
| Android  | `true`            | Your app's own screen     |

Keep `googlePayInApp: false` until Google has approved your app. See
[Google Pay on Android](google-pay.md). To show the payer, or a diagnostic screen, which one a
build will use, ask for it. It answers `inApp` or `browser`:

```dart
GetPayInCheckout.presentationFor(googlePayInApp: false);
```

## Using your own screen

`open()` draws the checkout on the provider's own route. To put it in a screen of your own
instead, render the view directly:

```dart
class CheckoutPage extends StatelessWidget {
  const CheckoutPage({required this.payment, super.key});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure checkout')),
      body: GetPayInCheckoutView(
        checkoutUrl: payment.checkoutUrl,
        returnUrl: 'myapp://payment-return',
        expectedInvoiceId: payment.invoiceId,
        onComplete: (result) => Navigator.of(context).pop(result),
        onLoadError: (message, detail) {
          debugPrint('GetPayIn checkout: $detail');
          showMessage(message);
        },
      ),
    );
  }
}
```

Three things to know when you do this:

1. **Handle `onLoadError`.** The provider shows the message and a close button when the
   checkout cannot load. Your own screen has to do that itself, or a failed load is a blank
   screen with no way out.
2. **Give the payer a way to cancel.** The provider's top bar does this. In your own screen
   it is your `AppBar` or back button, and you decide what a cancel means.
3. **Log `detail`, never show it.** It names the option and the value it got.

`onComplete` fires once per checkout. Changing `checkoutUrl` starts a new one.

## What the result is read from

GetPayIn's return link carries `success`, `invoice_id`, `invoice_status`, `message` and
`signature`. The package reads four of them:

1. `success`: `1` is `paid` and `0` is `notPaid`. Any other value, or no value, is
   `notPaid` with `unreadableReturnLink`.
2. `invoice_id` becomes `invoiceId`.
3. `invoice_status` becomes `invoiceStatus`. A paid link carrying anything but `PAID` is
   reported as `notPaid` with `unexpectedInvoiceStatus`.
4. `message` becomes `message`.

Names must match exactly, values are taken as sent, and the link is reported as `notPaid`
with `unreadableReturnLink` when it repeats **any** field or carries a name only a looser
reader would take for one of those four (`Success`, `invoiceId`, `%73uccess`). Nothing else
on the link is read, so a field GetPayIn does not send, such as `status=paid`, cannot change
the outcome. A forged link can still say `success=1`, which is why your server confirms the
payment.

The whole link stays in `returnUrl`, so your server can check its `signature`. If it does,
read the values from the link the same strict way: exact names, no case folding, no decoding
of names, and refuse a field that appears twice, `signature` included. A looser reader could
take a different `invoice_id` from the one the signature covers, and accept a genuine link
for one invoice as payment for another.

A valid signature is still not enough on its own. Before you trust it, also require
`invoice_id` to be digits only, `invoice_status` to be one of GetPayIn's statuses, and
`invoice_id` to be the invoice you created for this order. The `invoice.paid` webhook goes
from GetPayIn straight to your server and never passes through the phone, which is why it is
the one to fulfil orders on.

## Next

[API reference](api.md) · [Troubleshooting](troubleshooting.md)
