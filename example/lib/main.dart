// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

/// The scheme this app answers to, declared in `AndroidManifest.xml` and `Info.plist`.
const String appScheme = 'myapp';

/// The link the checkout sends the payer back to.
const String returnUrl = '$appScheme://payment-return';

/// Declares every scheme this app answers to, before anything can be paid for.
///
/// The checkout refuses all of them, so a page inside it cannot reach the app's own
/// deep-link routes.
void main() {
  declareHostAppSchemes(const <String>[appScheme]);
  runApp(const ExampleApp());
}

/// A harness for the checks that only a phone can make.
///
/// There is no server here on purpose. Paste a `checkout_url` that your own server, or the
/// GetPayIn dashboard, has already created and this opens it exactly as an integration
/// would: same provider, same options, same reading of the result. It is what
/// `CONTRIBUTING.md` asks you to run before a release.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetPayIn checkout',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0570DE)),
      home: GetPayInProvider(child: const CheckoutPage()),
    );
  }
}

/// The one screen: a checkout URL, how to open it, and what came back.
class CheckoutPage extends StatefulWidget {
  /// Creates the page.
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final TextEditingController _checkoutUrl = TextEditingController();

  bool _googlePayInApp = false;
  bool _busy = false;
  CheckoutResult? _result;
  String? _failure;

  @override
  void dispose() {
    _checkoutUrl.dispose();
    super.dispose();
  }

  /// Opens the pasted checkout and keeps whatever it answers.
  ///
  /// The invoice id is read off the URL rather than asked for separately, so the result is
  /// still bound to this checkout and a link naming another invoice is refused.
  Future<void> _pay() async {
    final url = _checkoutUrl.text.trim();

    setState(() {
      _busy = true;
      _result = null;
      _failure = null;
    });

    try {
      final result = await GetPayInCheckout.open(
        url,
        OpenCheckoutOptions(
          returnUrl: returnUrl,
          expectedInvoiceId: invoiceIdInCheckoutUrl(url),
          googlePayInApp: _googlePayInApp,
          title: 'Pay for your order',
        ),
      );

      setState(() => _result = result);
    } on GetPayInCheckoutError catch (error) {
      setState(() => _failure = error.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Where this build would draw the checkout, which is the first thing to check on a phone.
  String get _presentation => GetPayInCheckout.presentationFor(
        googlePayInApp: _googlePayInApp,
      ).wireName;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final failure = _failure;

    return Scaffold(
      appBar: AppBar(title: const Text('GetPayIn checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _checkoutUrl,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'checkout_url',
              helperText: 'From your server, or the GetPayIn dashboard.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            value: _googlePayInApp,
            onChanged: (value) => setState(() => _googlePayInApp = value),
            title: const Text('googlePayInApp'),
            subtitle: const Text(
              'On Android, draw it in the app\'s own screen. Ignored on iOS.',
            ),
          ),
          Text('This build would open it: $_presentation'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _checkoutUrl.text.trim().isEmpty || _busy ? null : _pay,
            child: Text(_busy ? 'Waiting for the payer…' : 'Open the checkout'),
          ),
          const SizedBox(height: 24),
          if (failure != null)
            _Outcome(title: 'It would not open', lines: <String>[failure]),
          if (result != null)
            _Outcome(
              title: result.status.wireName,
              lines: <String>[
                if (result.invoiceId != null) 'invoice ${result.invoiceId}',
                if (result.invoiceStatus != null)
                  'status ${result.invoiceStatus}',
                if (result.code != null) 'code ${result.code!.wireName}',
                if (result.message != null) result.message!,
                'Confirm the invoice.paid webhook before you deliver anything.',
              ],
            ),
        ],
      ),
    );
  }
}

/// What came back, as plainly as it can be put.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}
