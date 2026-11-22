// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

/// The scheme this app answers to, declared in both native projects.
const String appScheme = 'myapp';

/// The link the checkout sends the payer back to.
const String returnUrl = '$appScheme://payment-return';

void main() {
  declareHostAppSchemes(const <String>[appScheme]);
  runApp(const ExampleApp());
}

/// What your server returns when it creates a payment.
typedef Payment = ({String checkoutUrl, String invoiceId});

/// Asks your server to create the payment.
///
/// Your server calls `POST /api/integration/init` with your hash token and returns the
/// `checkout_url` and `invoice_id` it got back. The token never comes near the app.
Future<Payment> createPayment() async {
  throw UnimplementedError(
    'Point createPayment at your own server, which calls POST /api/integration/init.',
  );
}

/// The example app.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetPayIn checkout example',
      home: GetPayInProvider(child: const CheckoutPage()),
    );
  }
}

/// A page with one Pay button.
class CheckoutPage extends StatefulWidget {
  /// Creates the page.
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  /// Draw the checkout in the app's own screen on Android.
  ///
  /// Off until Google has approved the app, because before that an Android payer gets an
  /// app screen with no Google Pay button and no error saying why.
  static const bool _googlePayInApp = false;

  String _status = 'Ready';
  bool _paying = false;

  Future<void> _pay() async {
    setState(() {
      _paying = true;
      _status = 'Creating the payment…';
    });

    try {
      final payment = await createPayment();

      final result = await GetPayInCheckout.open(
        payment.checkoutUrl,
        OpenCheckoutOptions(
          returnUrl: returnUrl,
          expectedInvoiceId: payment.invoiceId,
          googlePayInApp: _googlePayInApp,
          title: 'Pay for your order',
        ),
      );

      _report(result);
    } on GetPayInSessionBusyError {
      return;
    } catch (error) {
      _show('$error');
    } finally {
      if (mounted) {
        setState(() => _paying = false);
      }
    }
  }

  /// Shows what came back, and confirms a paid result on the server.
  ///
  /// The result is a report of what the return link said, never proof of payment: only the
  /// `invoice.paid` webhook on your server may unlock, ship or credit anything.
  void _report(CheckoutResult result) {
    switch (result.status) {
      case CheckoutStatus.paid:
        _show(
            'Paid. Confirm invoice ${result.invoiceId} on your server before delivering.');
      case CheckoutStatus.notPaid:
        _show(result.message ?? 'The payment did not go through.');
      case CheckoutStatus.cancelled:
        _show('The payer closed the checkout.');
    }
  }

  void _show(String status) {
    if (mounted) {
      setState(() => _status = status);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GetPayIn checkout')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_status, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _paying ? null : _pay,
              child: const Text('Pay'),
            ),
            const SizedBox(height: 12),
            Text(
              'This build would open the checkout in: '
              '${GetPayInCheckout.presentationFor().wireName}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
