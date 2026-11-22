# getpayin_flutter_checkout

Take Apple Pay, Google Pay and card payments in your Flutter app. The hosted GetPayIn
checkout opens inside your app, under your app's own top bar, with no browser bar.

| Phone                                    | Where the checkout opens  | Payment methods  |
| ---------------------------------------- | ------------------------- | ---------------- |
| iPhone                                   | Your app's own screen     | Apple Pay, card  |
| Android, after Google approves your app  | Your app's own screen     | Google Pay, card |
| Android, before Google approves your app | The phone's browser sheet | Google Pay, card |

Google Pay is not offered on iPhone: Google only allows it in Safari, not inside apps.

This package holds no secret and signs nothing. Your server creates the payment and
confirms it; the app only shows the checkout and reports what came back.

## Install

```bash
flutter pub add getpayin_flutter_checkout
```

Then rebuild the app. The web view is native code, so a hot reload will not pick it up.

You also need a GetPayIn integration of type **Mobile App**, your app's URL scheme declared
in `AndroidManifest.xml` and `Info.plist`, and a server that creates and confirms payments.
[Setup](doc/setup.md) covers all three.

## Quick start

Declare the schemes your app answers to and mount the provider once:

```dart
import 'package:flutter/material.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

void main() {
  // Every scheme your app answers to. The checkout refuses all of them, so a page inside
  // it cannot drive your own deep-link routes.
  declareHostAppSchemes(const ['myapp']);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: GetPayInProvider(child: const ShopPage()),
    );
  }
}
```

Then take a payment:

```dart
// Your server calls POST /api/integration/init and sends back checkout_url.
final payment = await myApi.createPayment(order);

final result = await GetPayInCheckout.open(
  payment.checkoutUrl,
  OpenCheckoutOptions(
    returnUrl: 'myapp://payment-return', // must match your Mobile App Return Scheme
    expectedInvoiceId: payment.invoiceId, // ties the result to this checkout
    googlePayInApp: false, // set true only after Google approves your app
  ),
);

if (result.status == CheckoutStatus.paid) {
  await myApi.confirmPayment(result.invoiceId);
}
```

`result.status` is `paid`, `notPaid` or `cancelled`. Pass `expectedInvoiceId` whenever your
server gave you one: leaving it null turns off the check that a paid link belongs to *this*
invoice. A `notPaid` the package decided for itself carries a `code`, which a genuine
decline does not; see [Taking payments](doc/taking-payments.md#code-on-a-notpaid).

> **The result in the app is not proof of payment.** Your return scheme is public, so
> anything on the phone can forge that link. Confirm the `invoice.paid` webhook on your
> server before you deliver the order. [Security model](doc/security.md) explains what the
> package does on its side and why it is not enough on its own.

If you use `go_router`, add one redirect or payers will land on an unmatched route after
paying. See [Setup](doc/setup.md#go_router).

## Or take it on a sheet of your own

The same payment, with the checkout drawn as a payment sheet in your app — a wallet button,
the payer's saved cards, a card form, one pay button:

```dart
final result = await GetPayInPaymentSheet.show(
  context,
  PaymentSheetConfiguration(
    session: PayLinkFieldsSession.fromInit(payment)!, // your server's /init, mode: "fields"
    fieldsPageUrl: 'https://shop.example.com/paylink-fields.html',
    returnUrl: 'myapp://payment-return',
    expectedInvoiceId: invoiceId,
    amountLabel: r'$97.42',
    wallets: const [PaymentWallet.applePay, PaymentWallet.googlePay],
  ),
);
```

It runs on PayLink's hosted card fields, so the card number and security code are still
rendered by the gateway and never reach your app. It needs hosted fields enabled, a
registered origin and one page hosted there, and it moves you from PCI SAQ A to SAQ A-EP —
[The payment sheet](doc/payment-sheet.md) covers all of it, including the fallback to the
hosted checkout when the fields cannot run.

## Documentation

| Guide                                            | What is in it                                                                              |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| [Setup](doc/setup.md)                            | Prerequisites, install, the provider, routing, and the iOS and Android configuration.      |
| [Taking payments](doc/taking-payments.md)        | Opening a checkout, reading the result, confirming it, retries, and using your own screen. |
| [The payment sheet](doc/payment-sheet.md)        | The checkout as a sheet in your app, on PayLink's hosted card fields.                      |
| [Saving a card](doc/saving-a-card.md)            | Vaulting a card for next time, and why the token never reaches the app.                    |
| [Google Pay on Android](doc/google-pay.md)       | Getting Google's approval for in-app Google Pay, and the device requirements.              |
| [API reference](doc/api.md)                      | Every export, option, type and error.                                                      |
| [Security model](doc/security.md)                | What the package guarantees, what it cannot, and what your server must do.                 |
| [Troubleshooting](doc/troubleshooting.md)        | The failures that are silent: no wallet button, HTTP 403, a blank screen.                  |
| [Architecture](doc/architecture.md)              | How the package is laid out and why, for anyone changing it.                               |

Coming from the Expo package? [`@getpayin/expo-checkout`](https://www.npmjs.com/package/@getpayin/expo-checkout)
is the same checkout with the same rules; [Architecture](doc/architecture.md#differences-from-the-expo-package)
lists where this one had to differ.

## Contributing

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the layering rules, the house style and the
by-hand device checks. [`CHANGELOG.md`](CHANGELOG.md) records what changed.

## Reporting a vulnerability

Privately, please. See [`SECURITY.md`](SECURITY.md).

## License

MIT
