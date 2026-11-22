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
///
/// Built in with `--dart-define=PAYMENTS_SERVER=...`, so a machine's own address never has
/// to be typed on a phone, and never has to be committed either.
const String defaultPaymentsServer = String.fromEnvironment(
  'PAYMENTS_SERVER',
  defaultValue: 'http://10.0.2.2:8788',
);

/// The fields page to start with, from `--dart-define=FIELDS_PAGE=...`.
///
/// It has to be served from the origin registered for the integration, so there is no
/// sensible default: left out, the field starts empty and you type it.
const String defaultFieldsPage = String.fromEnvironment('FIELDS_PAGE');

/// Headers the fields page is asked for with while it is served through a dev tunnel.
///
/// ngrok's free tier answers an ordinary request with its own interstitial, which a web
/// view shows where the card fields should be; this header asks it for the page instead. An
/// origin that has never heard of the header ignores it, so the harness always sends it.
const Map<String, String> fieldsPageHeaders = <String, String>{
  'ngrok-skip-browser-warning': 'true',
};

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
  final TextEditingController _fieldsPage = TextEditingController(
    text: defaultFieldsPage,
  );

  bool _googlePayInApp = false;
  bool _useSheet = false;
  bool _collectBilling = false;
  bool _busy = false;
  String? _step;
  CheckoutResult? _result;
  String? _failure;

  @override
  void dispose() {
    _amount.dispose();
    _currency.dispose();
    _server.dispose();
    _fieldsPage.dispose();
    super.dispose();
  }

  /// Asks the dev server for a payment and takes it, on whichever surface is asked for.
  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _result = null;
      _failure = null;
      _step = 'Creating the payment…';
    });

    try {
      final payment = await _createPayment();
      final session = PayLinkFieldsSession.fromInit(payment.data);

      setState(() => _step = 'Waiting for the payer…');

      final result =
          _useSheet && session != null && _fieldsPage.text.trim().isNotEmpty
              ? await _showSheet(session)
              : await _openHostedCheckout(payment, session);

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

  /// Takes the payment on the sheet, with the card fields on the page you host.
  Future<CheckoutResult> _showSheet(PayLinkFieldsSession session) {
    return GetPayInPaymentSheet.show(
      context,
      PaymentSheetConfiguration(
        session: session,
        fieldsPageUrl: _fieldsPage.text.trim(),
        fieldsPageHeaders: fieldsPageHeaders,
        collectBillingAddress: _collectBilling,
        returnUrl: returnUrl,
        expectedInvoiceId: session.invoiceId,
        amountLabel:
            '${_amount.text.trim()} ${_currency.text.trim().toUpperCase()}',
        wallets: const <PaymentWallet>[
          PaymentWallet.applePay,
          PaymentWallet.googlePay,
        ],
      ),
    );
  }

  /// Takes the payment on the hosted checkout, and says why if the sheet was wanted.
  ///
  /// A company without hosted card fields, or a payment the fields cannot take, is the
  /// documented reason to send the payer here, so the harness does exactly that and names
  /// the code the API answered with.
  Future<CheckoutResult> _openHostedCheckout(
    _Payment payment,
    PayLinkFieldsSession? session,
  ) async {
    if (_useSheet) {
      setState(() => _failure = _whySheetIsNotShowing(payment, session));
    }

    return GetPayInCheckout.open(
      payment.checkoutUrl,
      OpenCheckoutOptions(
        returnUrl: returnUrl,
        expectedInvoiceId: invoiceIdInCheckoutUrl(payment.checkoutUrl),
        googlePayInApp: _googlePayInApp,
        title: 'Pay for your order',
      ),
    );
  }

  /// What is standing between this payment and the sheet.
  String _whySheetIsNotShowing(
      _Payment payment, PayLinkFieldsSession? session) {
    if (payment.fieldsError != null) {
      return 'The API answered ${payment.fieldsError}, so the hosted checkout was used.';
    }

    if (session == null) {
      return 'This payment carries no fields session, so the hosted checkout was used.';
    }

    return 'No fields page URL, so the hosted checkout was used. It has to be served from '
        '${session.origin}.';
  }

  /// What the dev server made for this amount.
  ///
  /// Everything the API needs signing is done there, so what reaches the phone is the
  /// answer `/init` gave and nothing else.
  Future<_Payment> _createPayment() async {
    final answer = await http.post(
      Uri.parse(_server.text.trim()),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, Object?>{
        'amount': _amount.text.trim(),
        'currency': _currency.text.trim().toUpperCase(),
        'title': 'Example order',
        'hosted_fields': _useSheet,
      }),
    );

    final body = jsonDecode(answer.body) as Map<String, Object?>;

    if (answer.statusCode >= 300 || body['data'] is! Map<String, Object?>) {
      throw StateError('${body['error'] ?? answer.body}');
    }

    return _Payment(
      data: body['data']! as Map<String, Object?>,
      fieldsError: body['fields_error'] as String?,
    );
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
            value: _useSheet,
            onChanged:
                _busy ? null : (value) => setState(() => _useSheet = value),
            title: const Text('Payment sheet'),
            subtitle: const Text(
              'Hosted card fields, on a page you serve from the registered origin.',
            ),
          ),
          if (_useSheet)
            TextField(
              controller: _fieldsPage,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Fields page URL',
                helperText:
                    'doc/paylink-fields.html, on your registered origin.',
                border: OutlineInputBorder(),
              ),
            ),
          if (_useSheet)
            SwitchListTile(
              value: _collectBilling,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _collectBilling = value),
              title: const Text('Billing address'),
              subtitle: const Text(
                'Ask for the address the card is billed to, which is what AVS checks.',
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

/// What the dev server answered for one payment.
class _Payment {
  const _Payment({required this.data, this.fieldsError});

  /// The `data` block `/init` returned, which the session is read out of.
  final Map<String, Object?> data;

  /// The code the API refused hosted fields with, when it refused them.
  final String? fieldsError;

  /// The hosted checkout, which every payment carries whatever else it has.
  String get checkoutUrl => data['checkout_url']! as String;
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
