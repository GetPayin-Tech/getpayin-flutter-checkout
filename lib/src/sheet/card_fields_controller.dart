import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'fields_page.dart';
import 'fields_protocol.dart';
import 'fields_session.dart';
import 'sheet_style.dart';

/// Drives the card box: the page that renders it, and everything it reports back.
///
/// The box is a web view because the card number and security code have to be rendered by
/// the gateway, and nothing else on the sheet is. This owns the whole of that boundary:
/// Flutter asks it to pay, it answers with what PayLink said.
///
/// Scripting this web view is deliberate and safe, unlike the hosted checkout's: the page
/// here shows no wallet, and WebKit only turns Apple Pay off on a page the host has
/// scripted. The wallet lives on its own, unscripted surface for exactly that reason.
class CardFieldsController extends ChangeNotifier {
  /// Creates a controller for one payment.
  CardFieldsController({
    required this.session,
    required this.pageUrl,
    this.style = const PaymentSheetStyle(),
    this.onPayment,
    this.onFailure,
  }) {
    _webView = _build();
  }

  /// The payment, as `/init` described it.
  final PayLinkFieldsSession session;

  /// The page you host on the origin registered for this integration.
  final String pageUrl;

  /// How the box is drawn, shared with the Flutter side of the sheet.
  final PaymentSheetStyle style;

  /// Called once the charge has answered, either way.
  final void Function(FieldsPayment payment)? onPayment;

  /// Called when the attempt could not be completed.
  final void Function(FieldsError error)? onFailure;

  late final WebViewController _webView;

  /// The controller the card box renders with.
  WebViewController get webView => _webView;

  bool _disposed = false;
  bool _ready = false;
  bool _authenticating = false;
  bool _charging = false;
  int? _amountMinor;
  String? _currency;
  String? _errorMessage;
  final Set<String> _validFields = <String>{};

  /// True once the fields are live and the gateway has priced the payment.
  bool get isReady => _ready;

  /// True while the issuer's 3-D Secure challenge is up.
  ///
  /// The challenge is framed by the SDK inside this web view and must stay framed that way,
  /// so the sheet gives the box the whole screen rather than drawing anything over it.
  bool get isAuthenticating => _authenticating;

  /// True once the charge is running and can no longer be called off.
  bool get isCharging => _charging;

  /// What will actually be charged, in minor units, once the gateway has said.
  int? get amountMinor => _amountMinor;

  /// The currency it will be charged in, once the gateway has said.
  String? get currency => _currency;

  /// The last thing worth showing the payer about the card they entered.
  String? get errorMessage => _errorMessage;

  /// True when every field in the box holds something chargeable.
  bool get isComplete =>
      _ready &&
      _validFields
          .containsAll(const <String>{'number', 'securityCode', 'expiry'});

  /// Charges the card in the box.
  ///
  /// Does nothing while a charge is already running: PayLink refuses the second one with
  /// `in_progress` anyway, and a payer who taps twice should not be told their payment
  /// failed.
  Future<void> pay() async {
    if (!isComplete || _charging || _authenticating) {
      return;
    }

    _charging = true;
    _errorMessage = null;
    notifyListeners();

    await _webView.runJavaScript(payCommand());
  }

  /// Takes the page down with the box.
  ///
  /// A charge can answer after the payer has closed the sheet, and the channel registered
  /// here would deliver it to a notifier that is gone. Nothing is received after this, and
  /// the page is told to let go of its fields and the capture context behind them.
  @override
  void dispose() {
    _disposed = true;
    unawaited(_letThePageGo());
    super.dispose();
  }

  /// Asks the page to tear its fields down, and does not care if it cannot.
  ///
  /// The web view may already be gone by the time this runs, which is the ordinary case
  /// when the whole sheet is being disposed, and nothing useful follows from saying so.
  Future<void> _letThePageGo() async {
    try {
      await _webView.runJavaScript(destroyCommand());
    } catch (_) {
      return;
    }
  }

  WebViewController _build() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        fieldsChannelName,
        onMessageReceived: (message) => _receive(message.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => unawaited(_start())),
      );

    if (!session.servesFrom(pageUrl)) {
      _fail(
        const FieldsError(
          failure: FieldsFailure.originNotAllowed,
          message:
              'The card fields page is not served from the registered origin.',
        ),
      );

      return controller;
    }

    unawaited(controller.loadRequest(Uri.parse(pageUrl)));

    return controller;
  }

  Future<void> _start() async {
    if (_ready) {
      return;
    }

    await _webView.runJavaScript(
      startFieldsCommand(
        clientToken: session.clientToken,
        style: style.toCssVariables(),
      ),
    );
  }

  void _receive(String raw) {
    final event = parseFieldsEvent(raw);

    if (event == null || _disposed) {
      return;
    }

    switch (event) {
      case FieldsReady(:final amountMinor, :final currency):
        _ready = true;
        _amountMinor = amountMinor;
        _currency = currency;
      case FieldsChanged(:final field, :final valid, :final empty):
        valid ? _validFields.add(field) : _validFields.remove(field);
        if (!empty && !valid) {
          _errorMessage = null;
        }
      case FieldsAuthenticating():
        _authenticating = true;
      case FieldsCharging():
        _charging = true;
      case FieldsPayment():
        _charging = false;
        _authenticating = false;
        onPayment?.call(event);
      case FieldsError():
        _fail(event);
        return;
      case FieldsWalletReady() || FieldsWalletError():
        return;
    }

    notifyListeners();
  }

  void _fail(FieldsError error) {
    if (_disposed) {
      return;
    }

    _charging = false;
    _authenticating = false;
    _errorMessage = error.message;
    notifyListeners();
    onFailure?.call(error);
  }
}
