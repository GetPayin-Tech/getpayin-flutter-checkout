import 'dart:convert';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:http/http.dart' as http;

/// The scheme this app answers to, declared in `AndroidManifest.xml` and `Info.plist`.
const String appScheme = 'myapp';

/// The link the checkout sends the payer back to.
const String returnUrl = '$appScheme://payment-return';

/// Where `example/tool/dev_server.py` is listening, on the machine that built this.
///
/// An app never creates a payment itself: `/init` is signed with the integration's hash
/// token, and anything that signs belongs on a server. The harness asks its own server for
/// a `checkout_url` exactly as a real app asks its backend.
const String defaultPaymentsServer = 'http://192.168.1.6:8788';

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
/// Give it an amount and a currency and it creates a payment through the dev server, then
/// opens it exactly as an integration would: same provider, same options, same reading of
/// the result. It is what `CONTRIBUTING.md` asks you to run before a release.
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

/// The one screen: what to charge, how to open it, and what came back.
class CheckoutPage extends StatefulWidget {
  /// Creates the page.
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final TextEditingController _amount = TextEditingController(text: '10.00');
  final TextEditingController _currency = TextEditingController(text: 'EGP');
  final TextEditingController _server = TextEditingController(
    text: defaultPaymentsServer,
  );

  bool _googlePayInApp = false;
  bool _busy = false;
  String? _step;
  CheckoutResult? _result;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _server.dispose();
    super.dispose();
  }

  /// Asks the dev server for a payment and opens whatever checkout it hands back.
  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _result = null;
      _failure = null;
      _step = 'Creating the payment…';
    });

    try {
      final checkoutUrl = await _createPayment();

      setState(() => _step = 'Waiting for the payer…');

      final result = await GetPayInCheckout.open(
        checkoutUrl,
        OpenCheckoutOptions(
          returnUrl: returnUrl,
          expectedInvoiceId: invoiceIdInCheckoutUrl(checkoutUrl),
          googlePayInApp: _googlePayInApp,
          title: 'Pay for your order',
        ),
      );

      setState(() => _result = result);
    } on GetPayInCheckoutError catch (error) {
      setState(() => _failure = error.message);
    } catch (error) {
      setState(() => _failure = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
      }
    }
  }

  /// The `checkout_url` the dev server created for this amount.
  ///
  /// Everything the API needs signing is done there, so what reaches the phone is a link
  /// and nothing else.
  Future<String> _createPayment() async {
    final answer = await http.post(
      Uri.parse(_server.text.trim()),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{
        'amount': _amount.text.trim(),
        'currency': _currency.text.trim().toUpperCase(),
        'title': 'Example order',
      }),
    );

    final body = jsonDecode(answer.body) as Map<String, Object?>;
    final checkoutUrl = body['checkout_url'];

    if (answer.statusCode >= 300 || checkoutUrl is! String) {
      throw StateError('${body['error'] ?? answer.body}');
    }

    return checkoutUrl;
  }

  /// Where this build would draw the checkout, which is the first thing to check on a phone.
  String get _presentation =>
      GetPayInCheckout.presentationFor(googlePayInApp: _googlePayInApp)
          .wireName;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final failure = _failure;

    return Scaffold(
      appBar: AppBar(title: const Text('GetPayIn checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _server,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Payments server',
              helperText: 'example/tool/dev_server.py, on your machine.',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            value: _googlePayInApp,
            onChanged: _busy
                ? null
                : (value) => setState(() => _googlePayInApp = value),
            title: const Text('googlePayInApp'),
            subtitle: const Text(
              'On Android, draw it in the app\'s own screen. Ignored on iOS.',
            ),
          ),
          Text('This build would open it: $_presentation'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: Text(_step ?? 'Create a payment and pay it'),
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
                'Only the invoice.paid webhook proves this. Confirm it on your server.',
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
