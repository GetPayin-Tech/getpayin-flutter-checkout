import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'billing_details.dart';
import 'card_fields_snapshot.dart';
import 'fields_page.dart';
import 'fields_protocol.dart';
import 'fields_session.dart';
import 'sheet_strings.dart';
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
    this.pageHeaders = const <String, String>{},
    this.collectsBilling = false,
    this.keepsTheCard = false,
    this.labels = const PaymentSheetStrings(),
    this.style = const PaymentSheetStyle(),
    this.onPayment,
    this.onFailure,
    this.onEvent,
  }) {
    _webView = _build();
  }

  /// The payment, as `/init` described it.
  final PayLinkFieldsSession session;

  /// The page you host on the origin registered for this integration.
  final String pageUrl;

  /// Headers the page is asked for with, for an origin that will not serve it without.
  ///
  /// A development tunnel or a gated staging origin can answer a plain request with its own
  /// interstitial, which is what the payer would then see where the card box should be.
  final Map<String, String> pageHeaders;

  /// Whether the box carries a name row, for a sheet that bills the card to an address.
  ///
  /// The name belongs in the box rather than beside it: it is one of the card's own rows in
  /// every card form a payer has met, and a box whose rows are drawn by two engines cannot
  /// be kept aligned. The address it belongs to is drawn by the sheet.
  final bool collectsBilling;

  /// Whether the box carries the row where the payer agrees to the card being kept.
  ///
  /// PayLink's own SDK writes that row, wording and all: the card networks want explicit
  /// agreement before a credential is stored, and only the party that showed the words can
  /// evidence what was agreed to. The sheet says where it goes, never what it says.
  final bool keepsTheCard;

  /// What the box's own rows say before the payer types.
  ///
  /// The gateway renders two of the four, so their placeholders are set through it rather
  /// than in the page's markup; they come from the same wording as the rest of the sheet so
  /// a translated sheet does not have an English card box in the middle of it.
  final PaymentSheetStrings labels;

  /// How the box is drawn, shared with the Flutter side of the sheet.
  final PaymentSheetStyle style;

  /// Called once the charge has answered, either way.
  final void Function(FieldsPayment payment)? onPayment;

  /// Called when the attempt could not be completed.
  final void Function(FieldsError error)? onFailure;

  /// Called with every event the page reports, for a sheet keeping a diagnostic.
  ///
  /// Separate from the two above because they are how the sheet works and this is only how
  /// it is watched: a listener here changes nothing and misses nothing.
  final void Function(FieldsEvent event)? onEvent;

  late final WebViewController _webView;

  /// The controller the card box renders with.
  WebViewController get webView => _webView;

  bool _disposed = false;
  CardFieldsSnapshot _snapshot = const CardFieldsSnapshot();

  /// Everything the box knows about itself, for a sheet that wants it in one piece.
  CardFieldsSnapshot get snapshot => _snapshot;

  /// True once the fields are live and the gateway has priced the payment.
  bool get isReady => _snapshot.ready;

  /// True while the issuer's 3-D Secure challenge is up.
  ///
  /// The challenge is framed by the SDK inside this web view and must stay framed that way,
  /// so the sheet gives the box the whole screen rather than drawing anything over it.
  bool get isAuthenticating => _snapshot.authenticating;

  /// True once the charge is running and can no longer be called off.
  bool get isCharging => _snapshot.charging;

  /// True once the gateway has this attempt's charge, whatever it answered since.
  bool get chargeStarted => _snapshot.chargeStarted;

  /// What will actually be charged, in minor units, once the gateway has said.
  int? get amountMinor => _snapshot.amountMinor;

  /// The currency it will be charged in, once the gateway has said.
  String? get currency => _snapshot.currency;

  /// The last thing worth showing the payer about the card they entered.
  String? get errorMessage => _snapshot.errorMessage;

  /// True when every field in the box holds something chargeable.
  bool get isComplete => _snapshot.isComplete;

  /// Charges the card in the box.
  ///
  /// Does nothing while a charge is already running: PayLink refuses the second one with
  /// `in_progress` anyway, and a payer who taps twice should not be told their payment
  /// failed.
  Future<void> pay({BillingDetails? billing}) async {
    if (!isComplete || isCharging || isAuthenticating) {
      return;
    }

    if (keepsTheCard && !_snapshot.hasConsent) {
      return;
    }

    _apply(
      _snapshot
          .copyWith(charging: true, chargeStarted: false)
          .withMessage(null),
    );

    await _webView.runJavaScript(
      payCommand(billing: billing, keepTheCard: keepsTheCard),
    );
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
      _reportWrongOrigin();

      return controller;
    }

    unawaited(controller.loadRequest(Uri.parse(pageUrl), headers: pageHeaders));

    return controller;
  }

  /// Tells the sheet the page is on the wrong origin, once this controller exists.
  ///
  /// A microtask rather than a call from here: this runs while the constructor is still
  /// running, and a listener that reaches back for the controller would find a field that
  /// is still being initialised. Nothing can have reached the page by then either, so
  /// nothing is lost by letting the turn finish first.
  void _reportWrongOrigin() {
    scheduleMicrotask(
      () => _fail(
        const FieldsError(
          failure: FieldsFailure.originNotAllowed,
          message:
              'The card fields page is not served from the registered origin.',
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (isReady) {
      return;
    }

    await _webView.runJavaScript(
      startFieldsCommand(
        clientToken: session.clientToken,
        sdkUrl: session.sdkUrl,
        style: style.toCssVariables(),
        collectName: collectsBilling,
        collectConsent: keepsTheCard,
        nameLabel: labels.nameOnCard,
        cardNumberLabel: labels.cardNumber,
        expiryLabel: labels.expiry,
        securityCodeLabel: labels.securityCode,
      ),
    );
  }

  void _receive(String raw) {
    final event = parseFieldsEvent(raw);

    if (event == null || _disposed) {
      return;
    }

    onEvent?.call(event);

    if (event is FieldsError) {
      _fail(event);

      return;
    }

    _apply(applyFieldsEvent(_snapshot, event));

    if (event is FieldsPayment) {
      onPayment?.call(event);
    }
  }

  /// Replaces what the box knows, and tells its listeners only when something moved.
  ///
  /// An event that says nothing about this box, which is any of the wallet's, hands back
  /// the snapshot it was given, and a sheet that rebuilt for it would be rebuilding for the
  /// surface next door.
  void _apply(CardFieldsSnapshot next) {
    if (identical(next, _snapshot)) {
      return;
    }

    _snapshot = next;
    notifyListeners();
  }

  void _fail(FieldsError error) {
    if (_disposed) {
      return;
    }

    _apply(applyFieldsEvent(_snapshot, error));
    onFailure?.call(error);
  }
}
