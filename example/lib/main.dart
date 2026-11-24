import 'dart:convert';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

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
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  declareHostAppSchemes(const <String>[appScheme]);
  runApp(ExampleApp(store: await DemoStore.open()));
}

/// A harness for the checks that only a phone can make.
///
/// Give it an amount and a currency and it creates a payment through the dev server, then
/// opens it exactly as an integration would: same provider, same options, same reading of
/// the result. It is what `CONTRIBUTING.md` asks you to run before a release.
class ExampleApp extends StatelessWidget {
  /// Creates the example app over what the last run left behind.
  const ExampleApp({required this.store, super.key});

  /// What the demo remembered.
  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetPayIn checkout',
      theme: ThemeData(
        colorSchemeSeed: brand,
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: brand,
          foregroundColor: Colors.white,
        ),
      ),
      home: GetPayInProvider(child: CheckoutPage(store: store)),
    );
  }
}

/// GetPayIn's own green, so the harness looks like the product it is testing.
const Color brand = Color(0xFF009C95);

/// The sheet, in the same green.
///
/// The package ships a Stripe-ish blue, which is a sensible default for a package and the
/// wrong colour for this app: the hosted checkout already draws itself in the company's own
/// colour, so a sheet left on the default is the one surface in the flow that looks borrowed.
const PaymentSheetStyle sheetStyle = PaymentSheetStyle(
  accent: brand,
  selectedBorder: brand,
);

/// What the page is drawn on, behind the cards.
const Color canvas = Color(0xFFF1F5F4);

/// The wording a payer agrees to before their card is kept.
///
/// One constant, shown to the payer and sent to PayLink as `tokenization_consent_text`, so
/// the words stored against the card are the words that were on screen. Two copies of this
/// is how an integrator ends up unable to evidence what was actually agreed to.
const String cardSaveConsent = 'Save my card for future payments.';

/// The currencies the demo offers, which is what the integration is set up for.
const List<String> currencies = <String>['EGP', 'EUR', 'USD'];

/// The one screen: what to charge, how to open it, and what came back.
class CheckoutPage extends StatefulWidget {
  /// Creates the page over what the last run left behind.
  const CheckoutPage({required this.store, super.key});

  /// What the demo remembered.
  final DemoStore store;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final DemoStore _store = widget.store;

  late final TextEditingController _firstName =
      _remembered('first_name', 'John');
  late final TextEditingController _lastName = _remembered('last_name', 'Doe');
  late final TextEditingController _email =
      _remembered('email', 'john.doe@example.com');
  late final TextEditingController _title =
      _remembered('title', 'Wireless Headphones x1');
  late final TextEditingController _amount = _remembered('amount', '10.00');
  late final TextEditingController _server =
      _remembered('server', defaultPaymentsServer);
  late final TextEditingController _fieldsPage =
      _remembered('fields_page', defaultFieldsPage);

  /// The integration the dev server should sign with, when it is not to use its own.
  ///
  /// Kept with the rest so a tester is not retyping an account every launch. It is written
  /// to this app's own storage, which on a developer's test phone is the trade they asked
  /// for; it is still never compiled in, and the signing still happens on the server.
  late final TextEditingController _baseUrl = _remembered('base_url', '');
  late final TextEditingController _publicToken =
      _remembered('public_token', '');
  late final TextEditingController _hashToken = _remembered('hash_token', '');

  late String _currency = _store.text('currency', 'EGP');
  late bool _googlePayInApp = _store.flag('google_pay_in_app');
  late bool _useSheet = _store.flag('use_sheet');
  late bool _collectBilling = _store.flag('collect_billing');
  late bool _keepCard = _store.flag('keep_card');
  bool _busy = false;
  String? _step;
  CheckoutResult? _result;
  String? _failure;
  String? _note;

  /// Everything this attempt did, in order, for a tester reporting back.
  ///
  /// Kept as plain lines rather than objects because its only reader is a person pasting it
  /// into a message. Nothing secret goes in: the hash token is never here, because it never
  /// leaves the dev server except as the one field the gear sends it in.
  late final List<String> _trace = _store.lines('trace');

  /// A field that starts on what the last run left in it, and saves what is typed.
  TextEditingController _remembered(String key, String fallback) {
    final controller = TextEditingController(text: _store.text(key, fallback));

    controller.addListener(() => _store.put(key, controller.text));

    return controller;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _title.dispose();
    _amount.dispose();
    _baseUrl.dispose();
    _publicToken.dispose();
    _hashToken.dispose();
    _server.dispose();
    _fieldsPage.dispose();
    super.dispose();
  }

  /// Where a throw came from, as one line a tester can paste.
  ///
  /// A crash reported as "Null check operator used on a null value" and nothing else is a
  /// crash nobody can place, so the frame it came from goes in the trace beside it.
  String _firstFrameOf(StackTrace stack) {
    final frames = stack.toString().split('\n');

    for (final frame in frames) {
      final line = frame.trim();

      if (line.isNotEmpty && !line.contains('<asynchronous')) {
        return line;
      }
    }

    return 'unknown frame';
  }

  /// Keeps the trace, so the question "what did it do last time" survives the app closing.
  void _rememberTrace() => _store.put('trace', List<String>.from(_trace));

  /// Notes one thing that happened, for the debug panel.
  void _say(String line) {
    final at = DateTime.now().toIso8601String().substring(11, 19);

    _trace.add('$at  $line');
  }

  /// Asks the dev server for a payment and takes it, on whichever surface is asked for.
  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _result = null;
      _failure = null;
      _note = null;
      _trace.clear();
      _step = 'Creating the payment…';
    });

    _say('pay $_priced  sheet=$_useSheet  billing=$_collectBilling  '
        'keepCard=$_keepCard  googlePayInApp=$_googlePayInApp');
    _say('platform ${defaultTargetPlatform.name}  opens in: $_presentation');
    _say('server: ${_server.text.trim()}');
    _say(
        'base url: ${_baseUrl.text.trim().isEmpty ? "the server's own" : _baseUrl.text.trim()}');
    _say('tokens overridden: '
        'public=${_publicToken.text.trim().isNotEmpty} '
        'hash=${_hashToken.text.trim().isNotEmpty}');

    if (_useSheet) {
      _say('fields page: ${_fieldsPage.text.trim()}');
    }

    try {
      final payment = await _createPayment();
      final session = PayLinkFieldsSession.fromInit(payment.data);

      if (session == null) {
        _say('session: none in the init answer');
      } else {
        _say('session: origin ${session.origin}');
        _say('session: sdk ${session.sdkUrl}');
        _say('session: invoice ${session.invoiceId}  '
            'token ${session.clientToken.length} chars  '
            'expires ${session.expiresAt ?? "unstated"}');
        _say('session: page served from the origin? '
            '${session.servesFrom(_fieldsPage.text.trim())}');
      }

      setState(() => _step = 'Waiting for the payer…');

      final onTheSheet =
          _useSheet && session != null && _fieldsPage.text.trim().isNotEmpty;

      _say('surface: ${onTheSheet ? 'payment sheet' : 'hosted checkout'}');

      final result = onTheSheet
          ? await _showSheet(session)
          : await _openHostedCheckout(payment, session);

      _say('result: ${result.status.wireName}'
          '${result.code == null ? '' : ' / ${result.code!.wireName}'}'
          '${result.invoiceStatus == null ? '' : ' / ${result.invoiceStatus}'}');

      setState(() => _result = result);
    } on GetPayInCheckoutError catch (error) {
      _say('threw: ${error.runtimeType} ${error.message}');
      setState(() => _failure = error.message);
    } catch (error, stack) {
      _say('threw: $error');
      _say('at: ${_firstFrameOf(stack)}');
      setState(() => _failure = '$error');
    } finally {
      _rememberTrace();

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
        style: sheetStyle,
        collectBillingAddress: _collectBilling,
        onDiagnostic: (note) => setState(() => _say('page: $note')),
        onHandover: (error) {
          _say('handover: ${error.failure.name}  ${error.message ?? ''}');
          setState(
            () => _note = 'The sheet handed over: ${error.failure.name}. '
                '${error.message ?? ''} '
                'The payment was taken on the hosted checkout.',
          );
        },
        returnUrl: returnUrl,
        expectedInvoiceId: session.invoiceId,
        amountLabel: _priced,
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
      final why = _whySheetIsNotShowing(payment, session);

      _say('no sheet: $why');
      setState(() => _note = why);
    }

    return GetPayInCheckout.open(
      payment.checkoutUrl,
      OpenCheckoutOptions(
        returnUrl: returnUrl,
        expectedInvoiceId: invoiceIdInCheckoutUrl(payment.checkoutUrl),
        googlePayInApp: _googlePayInApp,
        title: _title.text.trim(),
      ),
    );
  }

  /// Why this payment went to the hosted checkout rather than onto the sheet.
  ///
  /// Not a failure, and not shown as one: every branch below is a payment PayLink is willing
  /// to take somewhere else, and the payer takes it there. Saying "it would not open" over a
  /// payment that went through is the harness lying about its own result.
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
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _email.text.trim(),
        'amount': _amount.text.trim(),
        'currency': _currency,
        'title': _title.text.trim(),
        'hosted_fields': _useSheet,
        'tokenize': _keepCard,
        if (_keepCard) 'tokenization_consent_text': cardSaveConsent,
        if (_baseUrl.text.trim().isNotEmpty) 'base_url': _baseUrl.text.trim(),
        if (_publicToken.text.trim().isNotEmpty)
          'public_token': _publicToken.text.trim(),
        if (_hashToken.text.trim().isNotEmpty)
          'hash_token': _hashToken.text.trim(),
      }),
    );

    final body = jsonDecode(answer.body) as Map<String, Object?>;

    if (answer.statusCode >= 300 || body['data'] is! Map<String, Object?>) {
      throw StateError('${body['error'] ?? answer.body}');
    }

    final data = body['data']! as Map<String, Object?>;

    _say('init: invoice ${data['invoice_id']}  '
        'fields=${data.containsKey('fields')}  '
        'tokenization=${data['tokenization_id'] ?? 'none'}  '
        'refusal=${body['fields_error'] ?? 'none'}');

    return _Payment(
      data: data,
      fieldsError: body['fields_error'] as String?,
    );
  }

  /// Where this build would draw the checkout, which is the first thing to check on a phone.
  String get _presentation =>
      GetPayInCheckout.presentationFor(googlePayInApp: _googlePayInApp)
          .wireName;

  /// Opens the integration the dev server should sign this payment with.
  ///
  /// Left empty, the server uses the credentials on the machine it runs on, which is how it
  /// has always worked and the only way that keeps the hash token off the phone entirely.
  Future<void> _openSettings() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.viewInsetsOf(sheet).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Integration',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sent to the dev server, which signs with these instead of its own. '
              'Leave a field empty to keep what the server already has.',
              style: TextStyle(fontSize: 14, color: Color(0xFF6D6E78)),
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Base URL',
              controller: _baseUrl,
              enabled: true,
              keyboard: TextInputType.url,
              hint: 'https://pay.getpayin.com',
            ),
            _Field(
              label: 'Authentication token',
              controller: _publicToken,
              enabled: true,
            ),
            _Field(
              label: 'Hash token',
              controller: _hashToken,
              enabled: true,
              obscure: true,
              hint: 'Held in memory only, never written to the phone',
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(sheet).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: brand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Puts the whole trace on the clipboard, for pasting into a report.
  Future<void> _copyTrace() async {
    final result = _result;
    final report = <String>[
      'GetPayIn Flutter demo',
      'android  ${_useSheet ? 'sheet' : 'hosted'}  $_presentation',
      ..._trace,
      if (_note != null) 'note: $_note',
      if (_failure != null) 'failure: $_failure',
      if (result?.message != null) 'message: ${result!.message}',
    ];

    await Clipboard.setData(ClipboardData(text: report.join('\n')));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied')),
      );
    }
  }

  /// What the pay button says, and what the sheet labels its own.
  String get _priced => '${_amount.text.trim()} $_currency'.trim();

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final failure = _failure;
    final note = _note;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GetPayIn Demo',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Integration',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: <Widget>[
          const Text(
            'Your order',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'A physical-goods checkout powered by GetPayIn hosted payments.',
            style: TextStyle(fontSize: 15, color: Color(0xFF6D6E78)),
          ),
          const SizedBox(height: 16),
          _Card(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _Field(
                      label: 'First name',
                      controller: _firstName,
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Field(
                      label: 'Last name',
                      controller: _lastName,
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
              _Field(
                label: 'Email',
                controller: _email,
                enabled: !_busy,
                keyboard: TextInputType.emailAddress,
              ),
              _Field(label: 'Order title', controller: _title, enabled: !_busy),
              _Field(
                label: 'Amount',
                controller: _amount,
                enabled: !_busy,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              ),
              const _Label('Currency'),
              _Segmented(
                options: currencies,
                selected: _currency,
                enabled: !_busy,
                onChanged: (chosen) => setState(() => _currency = chosen),
              ),
              _Consent(
                text: cardSaveConsent,
                value: _keepCard,
                enabled: !_busy,
                onChanged: (value) => setState(() => _keepCard = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            children: <Widget>[
              _Toggle(
                title: 'Payment sheet',
                detail: 'Card fields in the app, on a page you serve from the '
                    'registered origin. Off: the hosted checkout.',
                value: _useSheet,
                enabled: !_busy,
                onChanged: (value) => setState(() => _useSheet = value),
              ),
              if (_useSheet) ...<Widget>[
                _Toggle(
                  title: 'Billing address',
                  detail: 'Ask for the address the card is billed to, which is '
                      'what the issuer checks.',
                  value: _collectBilling,
                  enabled: !_busy,
                  onChanged: (value) {
                    setState(() => _collectBilling = value);
                    _store.put('collect_billing', value);
                  },
                ),
              ],
              _Toggle(
                title: "Google Pay in the app's own screen",
                detail: 'Only after Google approves the app. Off: the browser '
                    'sheet.',
                value: _googlePayInApp,
                enabled: !_busy,
                onChanged: (value) {
                  setState(() => _googlePayInApp = value);
                  _store.put('google_pay_in_app', value);
                },
              ),
              Text(
                'Opens in: $_presentation',
                style: const TextStyle(fontSize: 14, color: Color(0xFF6D6E78)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Card(
            children: <Widget>[
              _Field(
                label: 'Payments server',
                controller: _server,
                enabled: !_busy,
                keyboard: TextInputType.url,
                hint: 'example/tool/dev_server.py, on your machine',
              ),
              if (_useSheet)
                _Field(
                  label: 'Fields page URL',
                  controller: _fieldsPage,
                  enabled: !_busy,
                  keyboard: TextInputType.url,
                  hint: 'paylink-fields.html, on your registered origin',
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _busy ? null : _pay,
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Pay $_priced',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          if (_step != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _step!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6D6E78)),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Demo only: the hash token lives on the dev server, never in this '
            'app. In production your own backend signs the request.',
            style: TextStyle(fontSize: 13, color: Color(0xFF8A8B94)),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 16),
            _Outcome(
                title: 'Taken on the hosted checkout', lines: <String>[note]),
          ],
          if (failure != null) ...<Widget>[
            const SizedBox(height: 16),
            _Outcome(title: 'It would not open', lines: <String>[failure]),
          ],
          if (_trace.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            _Debug(
              lines: _trace,
              onCopy: _copyTrace,
              onClear: () {
                setState(_trace.clear);
                _rememberTrace();
              },
            ),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: 16),
            _Outcome(
              title: result.status.wireName,
              lines: <String>[
                if (result.invoiceId != null) 'invoice ${result.invoiceId}',
                if (result.invoiceStatus != null)
                  'status ${result.invoiceStatus}',
                if (result.code != null) 'code ${result.code!.wireName}',
                if (result.message != null) result.message!,
                'Only the invoice.paid webhook proves this. Confirm it on '
                    'your server.',
              ],
            ),
          ],
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

/// A white panel with the demo's own corner and spacing.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// The small grey word over a field.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF42434E),
        ),
      ),
    );
  }
}

/// One labelled input, drawn the way the demo draws all of them.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    this.keyboard,
    this.hint,
    this.onChanged,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboard;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Label(label),
          TextField(
            controller: controller,
            enabled: enabled,
            autocorrect: false,
            obscureText: obscure,
            keyboardType: keyboard,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: _border(const Color(0xFFDFE3E8)),
              focusedBorder: _border(brand),
              disabledBorder: _border(const Color(0xFFEDEFF2)),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                hint!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF8A8B94)),
              ),
            ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
  }
}

/// The currency strip: one of a few choices, all of them visible.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final List<String> options;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            for (final option in options)
              Expanded(
                child: GestureDetector(
                  onTap: enabled ? () => onChanged(option) : null,
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: option == selected ? brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: option == selected
                            ? Colors.white
                            : const Color(0xFF42434E),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tick a payer gives before their card is kept, in the words they are given.
///
/// On the order screen rather than on the payment sheet, because PayLink is told the payer
/// agreed when the payment is created -- and a tick collected after that would be asserting
/// something that had already been asserted.
class _Consent extends StatelessWidget {
  const _Consent({
    required this.text,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String text;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                activeColor: brand,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged:
                    enabled ? (ticked) => onChanged(ticked ?? false) : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 15, color: Color(0xFF42434E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One switch, with the sentence that says what it changes.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.detail,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String detail;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6D6E78),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            activeThumbColor: Colors.white,
            activeTrackColor: brand,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// Everything the last attempt did, and a button that copies it.
///
/// A tester on a phone cannot read a log, so the app keeps its own and hands it over in one
/// tap. It carries no secret: the hash token never reaches this side of the wire except as
/// the field the gear sends, and that is not traced.
class _Debug extends StatelessWidget {
  const _Debug({
    required this.lines,
    required this.onCopy,
    required this.onClear,
  });

  final List<String> lines;
  final Future<void> Function() onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _Card(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'What happened',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8A8B94)),
            ),
            TextButton.icon(
              onPressed: () => onCopy(),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
              style: TextButton.styleFrom(foregroundColor: brand),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              line,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontFamily: 'monospace',
                color: Color(0xFF42434E),
              ),
            ),
          ),
      ],
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
    return _Card(
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line,
              style: const TextStyle(fontSize: 15, color: Color(0xFF42434E)),
            ),
          ),
      ],
    );
  }
}
