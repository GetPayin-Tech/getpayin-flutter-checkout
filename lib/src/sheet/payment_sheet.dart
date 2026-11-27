import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../checkout.dart';
import '../core/invoice_id.dart';
import '../core/messages.dart';
import '../core/session_guard.dart';
import '../core/return_url.dart';
import '../core/validate.dart';
import '../platform.dart';
import '../types.dart';
import 'amount.dart';
import 'billing_countries.dart';
import 'billing_form.dart';
import 'card_fields_controller.dart';
import 'fields_protocol.dart';
import 'fields_session.dart';
import 'saved_card.dart';
import 'sheet_parts.dart';
import 'sheet_strings.dart';
import 'sheet_style.dart';
import 'wallet_surface.dart';

/// Everything one run of the payment sheet needs.
class PaymentSheetConfiguration {
  /// Creates the configuration for one payment.
  const PaymentSheetConfiguration({
    required this.session,
    required this.fieldsPageUrl,
    required this.returnUrl,
    this.fieldsPageHeaders = const <String, String>{},
    this.collectBillingAddress = false,
    this.billingCountries = defaultBillingCountries,
    this.billingCountry = 'EG',
    this.successPause = const Duration(milliseconds: 1200),
    this.onHandover,
    this.onDiagnostic,
    this.keepTheCard = false,
    this.expectedInvoiceId,
    this.amountLabel,
    this.wallets = const <PaymentWallet>[],
    this.savedCards = const <SavedCard>[],
    this.chargeSavedCard,
    this.ownSchemes = const <String>[],
    this.style = const PaymentSheetStyle(),
    this.strings = const PaymentSheetStrings(),
    this.fallBackToHostedCheckout = true,
  });

  /// The payment your server created with `mode: "fields"`.
  final PayLinkFieldsSession session;

  /// The page you host on the origin registered for this integration.
  final String fieldsPageUrl;

  /// The link a wallet charge comes back to, and the one the hosted fallback uses.
  final String returnUrl;

  /// Headers the fields page is asked for with, for an origin that will not serve it
  /// without one.
  ///
  /// A development tunnel or a gated staging origin can answer a plain request with its own
  /// interstitial, which is what the payer would then see where the sheet should be.
  final Map<String, String> fieldsPageHeaders;

  /// Whether the payer is asked for the address their card is billed to.
  ///
  /// Off by default, and worth turning on only where the company collects one: the gateway
  /// renders the card number and the security code and nothing else, so without an address
  /// the charge goes out against the company's placeholder and the issuer's address check
  /// is matched against that. Turning it on adds a name row to the card box as well, since
  /// the gateway ignores an address that does not carry one.
  final bool collectBillingAddress;

  /// The countries the billing form offers. Narrow it, or translate it, as you like.
  final List<BillingCountry> billingCountries;

  /// The country the billing form starts on, as an ISO 3166-1 alpha-2 code.
  final String billingCountry;

  /// Whether the payer is asked to keep the card for next time, while paying with it.
  ///
  /// PayLink's own SDK draws that row and owns its wording, because the card networks want
  /// explicit agreement before a credential is stored and only the party that showed the
  /// words can evidence what was agreed to. The sheet gives it a place in the card box.
  ///
  /// Your company has to have card tokenization enabled, and the charge carries the
  /// agreement with it. Nothing is kept without the payer ticking it.
  final bool keepTheCard;

  /// Called with a line for everything the card box reports, when you want to watch it.
  ///
  /// For a diagnostic a tester can paste into a report, nothing more: it changes nothing
  /// about the payment and is never required. The lines say what happened and never what
  /// was typed.
  final void Function(String note)? onDiagnostic;

  /// Called when the sheet gives up and hands the payer to the hosted checkout.
  ///
  /// The handover is the right thing to do and the payer is served by it, but it used to be
  /// silent: an integrator saw a browser open with nothing to say why, and the reason is the
  /// only part they can act on. [FieldsError.failure] names it — a page on the wrong origin,
  /// a company without the fields, a session that has expired — and [FieldsError.message]
  /// says it in words, which is the only thing there is to go on when the code is one this
  /// package does not know.
  ///
  /// Never called for a decline or a mistyped card: those stay on the sheet for the payer to
  /// correct, and are not a handover.
  final void Function(FieldsError error)? onHandover;

  /// How long the sheet says the payment went through before it closes.
  ///
  /// A sheet that vanishes the instant the gateway answers leaves the payer wondering
  /// whether it did. Set it to [Duration.zero] to close as soon as the answer arrives.
  final Duration successPause;

  /// The invoice this payment is for, so a result naming another one is refused.
  ///
  /// Left out, the invoice `/init` reported for [session] is used: the session already
  /// names it. A saved card's charge is not held to either: your server's charge on a
  /// token makes an invoice of its own. See [chargeSavedCard].
  ///
  /// A value that is not an invoice id — empty text, a fraction — makes
  /// [GetPayInPaymentSheet.show] throw a [GetPayInConfigError] before the sheet opens, as
  /// [GetPayInCheckout.open] does: held to it, every payment would be refused.
  final Object? expectedInvoiceId;

  /// The invoice the card box, the wallet and the hosted fallback are held to.
  ///
  /// The session's own invoice only when it can be read: `/init` reaches the app through
  /// the integrator's server, and an id nobody can read would refuse every payment that
  /// went through and stop the hosted fallback from opening.
  Object? get _invoiceToBind =>
      expectedInvoiceId ??
      (invoiceIdFrom(session.invoiceId) == null ? null : session.invoiceId);

  /// What to show on the pay button until the gateway has priced the payment.
  final String? amountLabel;

  /// The wallets to offer. One is shown: the one that belongs on this platform.
  final List<PaymentWallet> wallets;

  /// The payer's vaulted cards, from your own backend.
  final List<SavedCard> savedCards;

  /// Charges a vaulted card.
  ///
  /// This is a call your server makes — charging a token is signed with your hash token,
  /// which never reaches the app — so the sheet hands you the card the payer picked and
  /// waits for what your server answers.
  ///
  /// When the issuer wants to challenge the payer, your server gets a URL for it, and this
  /// can open it with [GetPayInCheckout.open] and return what that settles with. The sheet
  /// lends that one checkout its place in the one-checkout-at-a-time guard.
  ///
  /// What it returns is a claim of payment, held to the rule every other one is: a `paid`
  /// naming an [CheckoutResult.invoiceStatus] other than `PAID` is not paid, and a `paid`
  /// without one is taken as it stands. So return the invoice your server's charge made,
  /// with its id and status as PayLink answered. Past that rule the sheet takes the result
  /// as your server reports it: your server confirms the charge.
  final Future<CheckoutResult> Function(SavedCard card)? chargeSavedCard;

  /// Other schemes this app answers to, refused like the return link's own.
  final List<String> ownSchemes;

  /// How the sheet is drawn, on both sides of the card box.
  final PaymentSheetStyle style;

  /// What the sheet says, for an app in another language.
  final PaymentSheetStrings strings;

  /// Send the payer to the hosted checkout when the fields cannot take this payment.
  ///
  /// On by default, and the reason the sheet can be used without a second thought: a
  /// company without hosted fields, an expired client token, a page on the wrong origin or
  /// a subscription the fields cannot take all end with the payer paying rather than stuck.
  /// A sale that also keeps the card is not among them: the sheet takes it, see
  /// [keepTheCard].
  final bool fallBackToHostedCheckout;

  /// The hosted checkout this payment falls back to.
  OpenCheckoutOptions get hostedOptions => OpenCheckoutOptions(
        returnUrl: returnUrl,
        expectedInvoiceId: _invoiceToBind,
        ownSchemes: ownSchemes,
      );
}

/// The hosted GetPayIn checkout, drawn as a payment sheet in your app.
///
/// The sheet is Flutter — the wallet button, the saved cards, the pay button, every label.
/// Only the card number and security code are not, because they have to be rendered by the
/// gateway; they sit in a box this sheet owns, on a page you host at your registered origin.
/// Every call behind it goes to PayLink: the capture context, payer authentication and the
/// charge are PayLink's endpoints, signed by a client token that names one payment.
///
/// Open it with [show]. The sheet ends by closing its own route, which is how it hands back
/// what the payment ended with, so it has no constructor to place it on a screen of your own:
/// there it would close your screen, and nobody would receive the result. A layout of your
/// own is built from the same pieces instead, as the payment sheet guide describes.
class GetPayInPaymentSheet extends StatefulWidget {
  /// Creates the sheet [show] presents, which tells it what an empty pop meant.
  const GetPayInPaymentSheet._shown({
    required this.configuration,
    required _SheetExit exit,
  }) : _exit = exit;

  /// The payment this sheet is taking.
  final PaymentSheetConfiguration configuration;

  /// Where the sheet keeps what a pop with no result means, for [show] to read.
  final _SheetExit _exit;

  /// Opens the hosted checkout, having told the integrator why the sheet could not.
  static Future<CheckoutResult> _handOver(
    PaymentSheetConfiguration configuration,
    FieldsError error,
  ) {
    configuration.onHandover?.call(error);

    return GetPayInCheckout.open(
      configuration.session.checkoutUrl,
      configuration.hostedOptions,
    );
  }

  /// Presents the sheet and completes once the payment ends.
  ///
  /// The result is a report of what PayLink said, never proof of payment: confirm the
  /// `payment.*` webhook on your server before you deliver anything.
  ///
  /// It cannot be dragged away. A drag cannot be refused once it is under way, and a charge
  /// the gateway already has must not be swiped off the screen; the sheet closes on its own
  /// control, on the barrier and on Back, each of which asks first.
  ///
  /// It holds the one-checkout-at-a-time guard while it is open, so a second sheet is
  /// refused and [GetPayInCheckout.busy] is true — which is what integrators are told to
  /// gate their pay button on. The guard is released before the hosted fallback opens,
  /// because that is a checkout of its own and takes the guard itself, and it is lent to
  /// the one checkout `chargeSavedCard` opens for an issuer's challenge.
  ///
  /// A pop the app makes in code cannot be refused and carries no result, so the sheet
  /// says what it would have meant: unconfirmed while anything is in flight, the payment
  /// once the sheet has one, cancelled otherwise.
  static Future<CheckoutResult> show(
    BuildContext context,
    PaymentSheetConfiguration configuration,
  ) async {
    assertExpectedInvoiceId(configuration.expectedInvoiceId);
    assertReturnUrl(configuration.returnUrl);
    assertCheckoutUrl(configuration.session.checkoutUrl);

    final exit = _SheetExit();
    final outcome = await checkoutGuard.run(
      () => Future.any<_SheetOutcome?>(<Future<_SheetOutcome?>>[
        exit.gone.future.then((_) => null),
        showModalBottomSheet<_SheetOutcome>(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0x00000000),
          barrierColor: const Color(0x66000000),
          enableDrag: false,
          builder: (_) => GetPayInPaymentSheet._shown(
            configuration: configuration,
            exit: exit,
          ),
        ),
      ]),
    );

    return switch (outcome) {
      _Settled(:final result) => result,
      _Fallback(:final error) => _handOver(configuration, error),
      null => exit.meaning?.call() ?? cancelledResult(closedByPayerMessage),
    };
  }

  @override
  State<GetPayInPaymentSheet> createState() => _GetPayInPaymentSheetState();
}

/// What a pop of the sheet's route with no result means, as the sheet last knew it.
///
/// Back and a tap outside are refused while anything is in flight, but a pop the app makes
/// in code — a sign-out that resets the screens, a `popUntil` — cannot be, and it carries
/// no result. Read once, as the route is popped, while the sheet is still mounted.
class _SheetExit {
  /// Answers what an empty pop means right now.
  CheckoutResult Function()? meaning;

  /// Completes when the sheet went without its route ever answering.
  ///
  /// A route answers when it is popped. An app that leaves the navigator the sheet was
  /// opened from — a shell route, a tab, a `MaterialApp` rebuilt on sign-out — takes the
  /// route with it and pops nothing, so the future `show()` is waiting on would stay
  /// pending for the rest of the process, with the one-checkout guard held behind it.
  final Completer<void> gone = Completer<void>();

  /// Reports the sheet gone, which only the first report means anything.
  void reportGone() {
    if (!gone.isCompleted) {
      gone.complete();
    }
  }
}

/// What the sheet closed with.
sealed class _SheetOutcome {
  const _SheetOutcome();
}

class _Settled extends _SheetOutcome {
  const _Settled(this.result);

  final CheckoutResult result;
}

class _Fallback extends _SheetOutcome {
  const _Fallback(this.error);

  /// What the fields could not do, for an integrator who has to fix it.
  final FieldsError error;
}

enum _Screen { methods, selectCard, newCard, done }

/// The share of the screen a 3-D Secure challenge is given, where there is room for it.
///
/// The issuer's page is a page, not a row: it carries its own instructions, a one-time code
/// field and a submit button, and a box sized for a card number scrolls all three. It is a
/// share rather than a number of points because the page is formatted by the issuer for the
/// window it is given, and a fixed box leaves a tall phone mostly empty while cropping the
/// page on a short one.
const double _challengeShareOfScreen = 0.85;

/// How tall the row with the close control above the challenge is.
///
/// Fixed, so the box under it can be sized from the room that is left.
const double _closeRowHeight = 40;

/// How long the sheet waits for a wallet's charge to start once the payer is back from the
/// wallet's own sheet.
///
/// Measured on an Android emulator against PayLink's sandbox: the page marked its charge
/// 4.0 and 4.4 seconds after Google Pay's sheet had closed. The wait is several times that,
/// because a payer on a slow network is the one most likely to press Back while nothing
/// seems to happen.
const Duration _walletGrace = Duration(seconds: 15);

/// How recent a touch on the wallet button has to be for the app leaving to count as the
/// payer opening the wallet.
///
/// Google Pay's sheet opened 0.6 seconds after the touch on the emulator; a slow phone takes
/// longer. Anything else the payer leaves for — a notification, a call — holds nothing.
const Duration _walletTouchWindow = Duration(seconds: 10);

/// How far a pointer may travel and still count as a tap on the wallet button.
///
/// Flutter's own touch slop, written here rather than imported: this is the sheet's rule
/// for what it treats as the payer reaching for the wallet, and it should not move when a
/// gesture constant does.
const double _walletTapSlop = 18;

class _GetPayInPaymentSheetState extends State<GetPayInPaymentSheet> {
  late final PaymentSheetConfiguration _config = widget.configuration;

  /// Built as the sheet opens rather than when the payer asks for it: the box has a page to
  /// load and fields to mount, and doing that behind the first screen is the difference
  /// between a card form that is there and one that arrives.
  late final CardFieldsController _card = CardFieldsController(
    session: _config.session,
    pageUrl: _config.fieldsPageUrl,
    pageHeaders: _config.fieldsPageHeaders,
    collectsBilling: _config.collectBillingAddress,
    keepsTheCard: _config.keepTheCard,
    labels: _config.strings,
    style: _config.style,
    onPayment: _onPayment,
    onFailure: _onFieldsFailure,
    onEvent: _report,
    onRefused: _config.onDiagnostic,
  );

  late final BillingFieldSet _billing =
      BillingFieldSet(country: _config.billingCountry);

  /// How many times the wallet has been offered, which is also its key.
  ///
  /// A surface that has reported one outcome will not report another: its navigation
  /// handler latches so a rebuilt sheet cannot report the same payment twice. That is the
  /// right rule for a rebuild and the wrong one for a second attempt, so a declined wallet
  /// gets a new surface rather than a reset latch.
  int _walletAttempt = 0;

  /// True from the page's mark that the wallet's charge is out until the wallet answers.
  bool _walletCharging = false;

  /// True while the wallet's page shows the issuer's 3-D Secure check.
  ///
  /// The check comes after the payer has approved the wallet and before the charge, and the
  /// issuer may yet pass it, so the sheet holds as it does for the card's check, and gives
  /// the wallet's page the room the check needs.
  bool _walletChallenge = false;

  /// True from the app going behind the wallet's own sheet until the wallet's charge is
  /// out, the wallet answers, or [_walletGrace] has passed since the payer came back.
  ///
  /// The page marks its charge only once the gateway has turned the wallet's answer into a
  /// token, seconds after the wallet's sheet has closed, and it cannot see that sheet at
  /// all. The app can, because the wallet puts it in the background. Without this hold, Back
  /// in those seconds reported a payment that went through as cancelled.
  bool _walletOpen = false;

  /// True from the payer opening the wallet until the wallet answers.
  ///
  /// A payer who dismisses the wallet leaves nothing on the page to say so, which is why the
  /// hold lets go on a timer. A wallet slower than that can still charge, so leaving the
  /// sheet after a wallet that never answered is reported unconfirmed, never cancelled.
  bool _walletUnanswered = false;

  /// True once a wallet charge went out that the sheet was not holding for.
  ///
  /// Its button had already left the screen, or was leaving it because another payment had
  /// started in the same instant, so the wallet's answer has nowhere to arrive. Whatever the
  /// sheet reports after that could hide a second payment, so it reports unconfirmed.
  bool _walletStray = false;

  /// A failure that means the card box cannot run, kept while another payment is in flight.
  ///
  /// The box loads behind the first screen, so it can fail while the wallet or a saved card
  /// is charging. Handing the payer over then would open a second way to pay for the same
  /// order, and `checkoutUnavailable` would say nothing was charged. It is acted on once
  /// that payment has ended without one.
  FieldsError? _heldFailure;

  /// Ends the hold on a wallet whose charge has not started since the payer came back.
  Timer? _walletRelease;

  /// True for [_walletTouchWindow] after a touch on the wallet button.
  ///
  /// The page cannot say the button was tapped: the button is the gateway's, in a frame of
  /// its own. The touch passes through the sheet first, so the sheet notes it there.
  bool _walletTouched = false;

  /// Forgets the touch on the wallet button once it is too old to explain the app leaving.
  Timer? _walletTouchExpiry;

  /// Tells the sheet when the app goes behind a wallet's own sheet, and when it is back.
  late final AppLifecycleListener _lifecycle;

  _Screen _screen = _Screen.methods;
  SavedCard? _selected;
  bool _charging = false;
  String? _error;

  /// The payment the sheet is showing as gone through, before it closes on it.
  ///
  /// Once there is one, nothing after it changes what the app is told: a late message from
  /// the page, a late answer from your server, or the payer leaving the success screen.
  CheckoutResult? _answer;

  /// True once the sheet's route is on its way out, by its own close or anyone's pop.
  ///
  /// The sheet stays mounted while it animates away, so an answer can still arrive; a
  /// second pop then would take the app's own screen under the sheet with it.
  bool _closed = false;

  /// True once nothing more may change what the sheet reports.
  bool get _finished => _closed || _answer != null || !mounted;

  @override
  void initState() {
    super.initState();
    _selected =
        _config.savedCards.where((card) => !card.hasExpired).firstOrNull;
    _card.addListener(_onCardChanged);
    widget._exit.meaning = _resultOfLeaving;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  /// Lets [GetPayInPaymentSheet.show] answer when the sheet goes without being closed.
  ///
  /// Only when it settled nothing itself: a sheet that popped with an answer, or that the
  /// payer closed, has already told `show()` what happened, and the route carries that.
  @override
  void dispose() {
    if (!_finished) {
      widget._exit.reportGone();
    }

    _walletRelease?.cancel();
    _walletTouchExpiry?.cancel();
    _lifecycle.dispose();
    _card.removeListener(_onCardChanged);
    _card.dispose();
    _billing.dispose();
    super.dispose();
  }

  void _onCardChanged() => setState(() {});

  /// Passes one page event on to whoever is watching, as a line.
  void _report(FieldsEvent event) =>
      _config.onDiagnostic?.call(describeFieldsEvent(event));

  void _onPayment(FieldsPayment payment) {
    _settle(
        resultFromPayment(payment, expectedInvoiceId: _config._invoiceToBind));
  }

  /// True from when the gateway has the charge until it answers.
  ///
  /// In between, nothing the page reports can mean "nothing was charged": the answer may
  /// simply not have come back.
  bool get _chargeIsOut => _card.chargeStarted;

  /// True while closing the sheet would lose the answer to something already under way.
  ///
  /// An attempt the card box is running, from the tap on Pay — the SDK asks the issuer and
  /// then charges, and goes on doing both after the sheet has gone — a charge the gateway
  /// has, a saved card your own server is charging, a wallet the payer has opened or whose
  /// charge the page has sent, or an issuer's challenge the payer is partway through, on the
  /// card or on the wallet. Each can finish after the sheet would have closed, and reporting
  /// that as cancelled reports a payment that may well have gone through as one that did not.
  bool get _isSettling =>
      _card.isCharging ||
      _card.isAuthenticating ||
      _chargeIsOut ||
      _charging ||
      _walletCharging ||
      _walletOpen ||
      _walletChallenge;

  /// True while charging a saved card would be a second payment for this order.
  ///
  /// Anything in flight, and a wallet the payer opened that has not answered. The hold on
  /// the sheet lets go after [_walletGrace] so a payer who dismissed the wallet is not
  /// stranded, but a wallet slower than that can still charge — and a saved card is charged
  /// on an invoice of its own, so the two would be two payments, which no per-invoice rule
  /// on PayLink's side can refuse. The card form stays open either way: it pays this
  /// invoice, and a second charge on one invoice is refused.
  bool get _savedCardWouldBeSecond => _isSettling || _walletUnanswered;

  /// True while a payment the card box is not running is in flight: a saved card, or a
  /// wallet the payer has opened, whose issuer's check is up, or whose charge is out.
  bool get _anotherPaymentIsOut =>
      _charging || _walletCharging || _walletOpen || _walletChallenge;

  /// The wallet the sheet shows right now, if any.
  ///
  /// Taken away while anything else is in flight, because it is one tap from a second
  /// charge, and kept while its own payment is, because its surface is where that runs.
  PaymentWallet? get _walletShown => _walletUnavailable ||
          (_isSettling && !_walletCharging && !_walletOpen && !_walletChallenge)
      ? null
      : PaymentWallet.forPlatform(currentPlatformName(), _config.wallets);

  /// True once the wallet's page has said it cannot show the wallet.
  bool _walletUnavailable = false;

  /// Takes the wallet away for good once its page says it cannot show it.
  ///
  /// It is never told so after the wallet's charge is marked, so nothing was charged through
  /// it, and a row left in place is empty space a touch on would still count as opening a
  /// wallet. A payer already in the wallet stays held as for any wallet that never answered.
  void _onWalletUnavailable() {
    if (_finished) {
      return;
    }

    _config.onDiagnostic?.call(
      'wallet unavailable: its page could not show it (a page that did not load, '
      'an SDK address it was not made for, or no wallet on this phone)',
    );
    setState(() => _walletUnavailable = true);
  }

  /// Where a touch on the wallet row went down, until it is lifted or cancelled.
  ///
  /// The row is a web view: the tap that opens the wallet happens inside it, where nothing
  /// here can see it. A pointer going down over the row is the whole signal there is, and
  /// taking that alone counted the start of a scroll as a wallet the payer had opened —
  /// enough to hold the sheet, turn saved cards off for the rest of it, and report a
  /// deliberate close as unconfirmed. A tap is a pointer that goes down and comes up
  /// without travelling, which is the most this side can tell.
  Offset? _walletPointerAt;

  /// Notes a tap on the wallet button, for [_onLifecycle] to read.
  void _onWalletTouched(Offset at) {
    final from = _walletPointerAt;

    _walletPointerAt = null;

    if (from == null || (at - from).distance > _walletTapSlop) {
      return;
    }

    _walletTouched = true;
    _walletTouchExpiry?.cancel();
    _walletTouchExpiry =
        Timer(_walletTouchWindow, () => _walletTouched = false);
  }

  /// Holds the sheet while the payer is in the wallet's own sheet, and for a while after.
  ///
  /// Any state but resumed counts as leaving, as it does for the browser checkout: Android
  /// pauses the app behind Google Pay, iOS makes it inactive behind Apple Pay. It counts as
  /// the wallet only on the screen that shows it, and only right after a touch on its
  /// button, so a payer who pulls down a notification, takes a call or switches apps to copy
  /// a card number is held by nothing and can still cancel.
  void _onLifecycle(AppLifecycleState state) {
    if (_finished) {
      return;
    }

    if (state != AppLifecycleState.resumed) {
      if (_screen != _Screen.methods ||
          _walletShown == null ||
          _walletCharging ||
          !_walletTouched) {
        return;
      }

      _walletRelease?.cancel();
      setState(() {
        _walletOpen = true;
        _walletUnanswered = true;
        _error = null;
      });

      return;
    }

    if (_walletOpen) {
      _walletRelease?.cancel();
      _walletRelease = Timer(_walletGrace, _releaseWallet);
    }
  }

  /// Lets the payer use the sheet again after a wallet that started no charge.
  ///
  /// Unless a wallet charge nobody was holding for came in while the payer was away: that
  /// charge can still go through, so freeing the sheet now would let a second payment start.
  void _releaseWallet() {
    if (_finished) {
      return;
    }

    setState(() => _walletOpen = false);

    if (_walletStray) {
      _settle(_unconfirmed);

      return;
    }

    _takeHeldFailure();
  }

  /// What the sheet settles with when a charge may have gone through and nobody knows.
  ///
  /// Always the sheet's own words. What the page or your server said goes to the log: it
  /// may well say to try another card, which is how one payment becomes two.
  CheckoutResult get _unconfirmed => CheckoutResult(
        status: CheckoutStatus.notPaid,
        code: CheckoutResultCode.outcomeUnknown,
        message: _config.strings.outcomeUnknown,
      );

  /// What leaving the sheet right now means: the payment it is showing, unconfirmed while
  /// anything is in flight or a wallet the payer opened has not answered, and cancelled
  /// otherwise.
  CheckoutResult _resultOfLeaving() =>
      _answer ??
      (_isSettling || _walletUnanswered || _walletStray
          ? _unconfirmed
          : cancelledResult(closedByPayerMessage));

  /// Closes the sheet at the payer's own request.
  ///
  /// Always allowed, because a charge can hang and a sheet that cannot be closed then has to
  /// be killed with the app. While something is in flight it is reported as unconfirmed,
  /// never as cancelled.
  void _closeByPayer() => _close(_Settled(_resultOfLeaving()));

  /// Decides what a failure the card box reported means for this payment.
  ///
  /// After the charge left, or after a wallet charge nobody was holding for, nobody knows
  /// whether this payer paid, so the sheet settles unconfirmed. Before that, a failure
  /// about this attempt is shown for another try, and one that means the fields cannot run
  /// hands the payer to the hosted checkout. Once the sheet has its answer, a failure
  /// changes nothing.
  ///
  /// While another payment is in flight, the box is not what the payer is paying with. A
  /// failure that means it cannot run waits for that payment's answer, and any other is
  /// left to the box's own message: offering a retry would free the sheet mid-charge. That
  /// includes PayLink saying the invoice is already paid, which is what the wallet's own
  /// charge does to it: its answer says more than the box can.
  ///
  /// An invoice already paid with nothing else in flight settles unconfirmed: something
  /// paid it, and the sheet cannot say what.
  ///
  /// After a wallet the payer opened that never answered, a failure that means the box
  /// cannot run settles unconfirmed. That wallet can still charge, so the hosted checkout
  /// would be a second way to pay, and `checkoutUnavailable` would say nothing was charged.
  void _onFieldsFailure(FieldsError error) {
    if (_finished) {
      return;
    }

    if (_chargeIsOut || _walletStray) {
      _settle(_unconfirmed);

      return;
    }

    if (_anotherPaymentIsOut) {
      if (error.failure.fatal) {
        _heldFailure = error;
      }

      return;
    }

    if (error.failure == FieldsFailure.alreadyPaid) {
      _settle(_unconfirmed);

      return;
    }

    if (!error.failure.sendsPayerToHostedCheckout) {
      _showRetryable(error.message ?? _config.strings.cardDeclined);

      return;
    }

    if (_walletUnanswered) {
      _settle(_unconfirmed);

      return;
    }

    if (!_config.fallBackToHostedCheckout) {
      _settle(
        CheckoutResult(
          status: CheckoutStatus.notPaid,
          code: CheckoutResultCode.checkoutUnavailable,
          message: error.message ?? _config.strings.unavailable,
        ),
      );

      return;
    }

    _close(_Fallback(error));
  }

  /// Ends the sheet on [result], or offers another try when it was a plain decline.
  ///
  /// Does nothing once the sheet has its answer or is closing: a charge can answer after the
  /// payer closed it, and the sheet has already reported what it knew. After a wallet
  /// charge nobody was holding for, any answer ends it unconfirmed: another try could be a
  /// second payment, and a payment could be one of two.
  void _settle(CheckoutResult result) {
    if (_finished) {
      return;
    }

    if (_walletStray) {
      _close(_Settled(_unconfirmed));

      return;
    }

    if (result.status == CheckoutStatus.notPaid && result.code == null) {
      _showRetryable(result.message ?? _config.strings.cardDeclined);
      _takeHeldFailure();

      return;
    }

    if (result.status == CheckoutStatus.paid &&
        _config.successPause > Duration.zero) {
      _sayItWentThrough(result);

      return;
    }

    _close(_Settled(result));
  }

  /// Acts on a card-box failure kept while another payment was in flight, now that it has
  /// ended without a payment.
  void _takeHeldFailure() {
    final held = _heldFailure;

    _heldFailure = null;

    if (held != null) {
      _onFieldsFailure(held);
    }
  }

  /// Tells the payer the payment went through, then closes on the same result.
  ///
  /// The sheet is the last thing the payer sees of their own payment, and closing the
  /// moment the gateway answers reads as the sheet giving up rather than as it finishing.
  /// It is still only a report of what PayLink said, not proof: the webhook is that.
  void _sayItWentThrough(CheckoutResult result) {
    setState(() {
      _answer = result;
      _screen = _Screen.done;
    });

    Future<void>.delayed(_config.successPause, () => _close(_Settled(result)));
  }

  /// Pops the sheet's route with [outcome], once.
  ///
  /// Only the sheet's own route. The billing form's country list is a route too, open over
  /// the sheet, and a result can arrive while the payer is choosing: popping whatever is on
  /// top would close the list with the sheet's outcome and leave the sheet up, with its close
  /// already spent. Anything over the sheet goes first, with no answer.
  ///
  /// A route the app has already taken away, as a reset of its screens does, is left alone.
  /// The app was told what leaving meant as the route went, and popping now would take the
  /// app's own new screens with it.
  void _close(_SheetOutcome outcome) {
    if (!mounted || _closed) {
      return;
    }

    _closed = true;

    final sheet = ModalRoute.of(context);

    if (sheet != null && !sheet.isActive) {
      return;
    }

    final navigator = Navigator.of(context);

    if (sheet != null) {
      navigator.popUntil((route) => route == sheet);
    }

    navigator.pop(outcome);
  }

  /// Notes that the route was popped by something other than the sheet's own close.
  void _onPopped(bool didPop, Object? _) {
    if (didPop) {
      _closed = true;
    }
  }

  Future<void> _paySaved() async {
    final card = _selected;
    final charge = _config.chargeSavedCard;

    if (card == null || charge == null || _savedCardWouldBeSecond) {
      return;
    }

    setState(() {
      _charging = true;
      _error = null;
    });

    try {
      _settle(_asSavedCardAnswer(await checkoutGuard.lend(() => charge(card))));
    } catch (cause) {
      _reportChargeFailure(cause);
    }
  }

  /// What a saved card's charge answered, read the way the sheet reads anything in flight.
  ///
  /// `cancelled` is never an answer to a charge your server has started. It is what an
  /// issuer's challenge settles with when the payer closes it, and a payer can close it after
  /// answering the issuer, with the charge already on its way; the sheet cannot tell the two
  /// apart, so it reports neither as nothing having happened.
  ///
  /// Anything else is a claim of payment, and settles the way every other one does. A charge
  /// on a token makes its own invoice, so it is not held to
  /// [PaymentSheetConfiguration.expectedInvoiceId].
  CheckoutResult _asSavedCardAnswer(CheckoutResult result) =>
      result.status == CheckoutStatus.cancelled
          ? _unconfirmed
          : settlePaidClaim(result);

  /// Takes what the wallet answered, and offers it again if the payer can try once more.
  ///
  /// A wallet decline leaves the sheet open, so the surface that reported it has to go: it
  /// has already latched, and the next answer would arrive to nobody. An answer that comes
  /// after the sheet has its answer or is closing is dropped: it has already reported one.
  void _onWalletResult(CheckoutResult result) {
    if (_finished) {
      return;
    }

    final declined =
        result.status == CheckoutStatus.notPaid && result.code == null;

    _walletRelease?.cancel();
    setState(() {
      _walletCharging = false;
      _walletOpen = false;
      _walletChallenge = false;
      _walletUnanswered = false;

      if (declined) {
        _walletAttempt++;
      }
    });

    _settle(result);
  }

  /// Holds the sheet still once the wallet page says its charge is out.
  ///
  /// The mark can arrive after the payer has left, from a surface still on its way out, and
  /// a sheet that is finished has nothing to hold. A mark from a button the sheet is about
  /// to take away, because the payer moved on or another payment has just started, is a
  /// charge nobody is holding for.
  void _onWalletCharging() {
    if (_finished) {
      return;
    }

    if (_screen != _Screen.methods || _walletShown == null) {
      _noteStrayWalletCharge();

      return;
    }

    _walletRelease?.cancel();
    setState(() {
      _walletCharging = true;
      _walletOpen = false;
      _walletChallenge = false;
      _error = null;
    });
  }

  /// Gives the wallet the whole sheet while the issuer's check is up on its page, and gives
  /// the row back when the check has gone with no charge.
  ///
  /// While it is up the sheet holds, as for the card's check: the issuer may yet pass it and
  /// the charge follow. A check passed is followed by the charge's own mark, which takes over
  /// the hold. One that has gone with no charge is the wallet's answer for this attempt, so
  /// the sheet is as it was before the wallet, unless a charge nobody was holding for came in
  /// meanwhile, or a card-box failure was kept for after it.
  ///
  /// A check from a button the sheet is about to take away — the payer has just moved to
  /// the card, or another payment has just started — is ignored. That page is emptied as the
  /// button goes, before any charge, and taking the mark would bring the wallet back beside
  /// the other payment, or hold a card screen that has no wallet on it.
  void _onWalletChallenge(bool showing) {
    if (_finished || (!showing && !_walletChallenge)) {
      return;
    }

    if (showing && (_screen != _Screen.methods || _walletShown == null)) {
      _config.onDiagnostic?.call(
        'wallet check ignored: its button was leaving as another way to pay started',
      );

      return;
    }

    if (showing) {
      _walletRelease?.cancel();
      setState(() {
        _walletChallenge = true;
        _walletOpen = false;
        _error = null;
      });

      return;
    }

    setState(() {
      _walletChallenge = false;
      _walletUnanswered = false;
    });

    if (_walletStray && !_isSettling) {
      _settle(_unconfirmed);

      return;
    }

    _takeHeldFailure();
  }

  /// Takes a mark from a wallet button that has already left the screen.
  ///
  /// Always a charge nobody is holding for, even with a new button in its place: the answer
  /// would arrive on the old page, which is gone, so holding for the new one would hold for
  /// an answer that never comes.
  void _onWalletChargingAfterLeaving() {
    if (_finished) {
      return;
    }

    _noteStrayWalletCharge();
  }

  /// Notes a wallet charge nobody is holding for.
  ///
  /// The sheet ends unconfirmed on the next answer, when the hold on an opened wallet lets
  /// go, or at once when nothing else is in flight.
  void _noteStrayWalletCharge() {
    _walletStray = true;

    if (!_isSettling) {
      _settle(_unconfirmed);
    }
  }

  /// Moves the payer to [screen], unless a payment is in flight.
  ///
  /// Checked when the tap lands, not only when the row was drawn: the wallet page can mark
  /// its charge in between, and leaving the wallet's screen then takes away the button its
  /// answer arrives on.
  void _openScreen(_Screen screen) {
    if (_isSettling) {
      return;
    }

    setState(() => _screen = screen);
  }

  /// Ends a saved-card charge whose answer never came.
  ///
  /// `chargeSavedCard` is the integrator's own call to their own server, so an exception
  /// here is a network that went away rather than a card that was refused — and never
  /// offered as one: their server may have charged the card and then lost the answer, so
  /// "try another card" is how one payment becomes two. The sheet settles with a code that
  /// says to read the invoice, and in a debug build the cause goes to the log, where
  /// developer text belongs. Only there: what your server threw can carry its own request,
  /// and a release build's log is read by whoever can read the phone's.
  void _reportChargeFailure(Object cause) {
    if (kDebugMode) {
      debugPrint('GetPayIn payment sheet: $cause');
    }

    _settle(_unconfirmed);
  }

  /// Shows the payer what went wrong with this attempt, and lets them make another.
  ///
  /// Its callers have already checked the sheet is not finished: a charge can answer after
  /// the payer has closed the sheet, and a sheet that is gone has nothing to show.
  void _showRetryable(String message) {
    setState(() {
      _charging = false;
      _error = message;
    });
  }

  String get _amountLabel {
    final minor = _card.amountMinor;
    final currency = _card.currency;

    if (minor != null && currency != null && currency.isNotEmpty) {
      return formatAmount(minor, currency);
    }

    return _config.amountLabel ?? '';
  }

  /// How tall the sheet may grow before its content starts scrolling instead.
  ///
  /// A card screen that collects a billing address is taller than a short phone with the
  /// keyboard up, and a sheet that cannot scroll simply hides the pay button under the
  /// bottom edge. The space the keyboard takes is already out of this, because the whole
  /// sheet is inset by it.
  double _tallestIn(BuildContext context) {
    final media = MediaQuery.of(context);

    // The bottom inset, the home indicator's, is drawn inside the sheet but outside this
    // limit, so it comes off too. With the keyboard up it is zero: the keyboard covers it.
    return math.max(
      240,
      media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          _statusBarIn(context) -
          24,
    );
  }

  /// The top of the screen the phone keeps for itself: the status bar, a notch, an island.
  ///
  /// Read from the view rather than the sheet's own media query: a modal bottom sheet's
  /// route takes the top inset out of that, so the sheet would be told there is none and
  /// grow up under the status bar.
  double _statusBarIn(BuildContext context) {
    final view = View.of(context);

    return view.padding.top / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    final style = _config.style;

    return PopScope<Object?>(
      canPop: !_isSettling,
      onPopInvokedWithResult: _onPopped,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Material(
          color: style.background,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(style.radius * 2)),
          ),
          child: SafeArea(
            top: false,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _tallestIn(context)),
                child: SingleChildScrollView(
                  padding: _contentPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _screenContent(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The space around what the sheet is showing, which the challenge does not get.
  ///
  /// Everything else on the sheet is drawn by this package and is padded like the rest of
  /// it. The challenge is the issuer's own page, framed by the SDK, and every point taken
  /// off its width is taken off a page formatted for a window it was told about.
  EdgeInsets get _contentPadding {
    return _card.isAuthenticating || _walletChallenge
        ? const EdgeInsets.fromLTRB(0, 8, 0, 0)
        : const EdgeInsets.fromLTRB(16, 8, 16, 16);
  }

  List<Widget> _screenContent(BuildContext context) {
    if (_card.isAuthenticating) {
      return _challenge(context);
    }

    return switch (_screen) {
      _Screen.methods => _methods(),
      _Screen.selectCard => _selectCard(),
      _Screen.newCard => _newCard(),
      _Screen.done => _done(),
    };
  }

  /// The first screen: the wallet, the saved card and a new card, with one pay button.
  ///
  /// While a charge runs, every other way to pay on it is shut: the wallet is taken away
  /// and the rows stop answering, because each is one tap from a second charge for the same
  /// order. They come back with the answer. A wallet charge keeps its own surface, because
  /// that surface is what its answer arrives on.
  List<Widget> _methods() {
    final strings = _config.strings;
    final settling = _isSettling;
    final wallet = _walletShown;
    final saved = _config.savedCards;
    final savedCardHeld = _savedCardWouldBeSecond;
    final canPickCard = saved.length > 1 && !savedCardHeld;
    final canPaySaved =
        _selected != null && _config.chargeSavedCard != null && !savedCardHeld;
    final walletRow = wallet == null ? null : _walletRow(wallet);

    if (_walletChallenge && walletRow != null) {
      return <Widget>[
        SizedBox(
          height: _closeRowHeight,
          child: SheetHeader(
            style: _config.style,
            semanticLabel: strings.close,
            onPressed: _closeByPayer,
          ),
        ),
        walletRow,
      ];
    }

    return <Widget>[
      SheetHeader(
        style: _config.style,
        semanticLabel: strings.close,
        onPressed: _closeByPayer,
      ),
      if (walletRow != null) ...<Widget>[
        walletRow,
        const SizedBox(height: 16),
        OrDivider(label: strings.orPayUsing, style: _config.style),
        const SizedBox(height: 16),
      ],
      if (saved.isNotEmpty && _selected != null) ...<Widget>[
        SectionLabel(strings.saved, style: _config.style),
        MethodRow(
          style: _config.style,
          selected: true,
          leading: BrandMark(brand: _selected?.brand ?? CardBrand.unknown),
          title: '•••• ${_selected?.last4 ?? ''}',
          trailing: canPickCard
              ? LinkText(
                  strings.viewMore,
                  style: _config.style,
                  onTap: () => _openScreen(_Screen.selectCard),
                )
              : null,
          onTap: canPickCard ? () => _openScreen(_Screen.selectCard) : null,
        ),
        const SizedBox(height: 16),
      ],
      SectionLabel(strings.newPaymentMethod, style: _config.style),
      MethodRow(
        style: _config.style,
        leading: Icon(Icons.credit_card, size: 20, color: _config.style.text),
        title: strings.newCard,
        onTap: settling ? null : () => _openScreen(_Screen.newCard),
      ),
      if (_error != null) ErrorText(_error!, style: _config.style),
      const SizedBox(height: 16),
      PayButton(
        label: '${_config.strings.pay} $_amountLabel'.trim(),
        style: _config.style,
        busy: _charging,
        onPressed: canPaySaved ? _paySaved : null,
      ),
    ];
  }

  /// The wallet's button, or, while the issuer's check is up on its page, the room the check
  /// needs.
  ///
  /// The same surface either way, keyed so it keeps its place when everything around it
  /// goes: a new surface loads a new page, and the check on the old one would be lost. The
  /// check is the issuer's own page, drawn by the SDK over the wallet's, so it gets the
  /// card's check's height and no rounding.
  Widget _walletRow(PaymentWallet wallet) {
    return ClipRRect(
      key: const ValueKey<String>('wallet-row'),
      borderRadius: BorderRadius.circular(
        _walletChallenge ? 0 : _config.style.radius,
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _walletPointerAt = event.position,
        onPointerUp: (event) => _onWalletTouched(event.position),
        onPointerCancel: (_) => _walletPointerAt = null,
        child: WalletSurface(
          key: ValueKey<int>(_walletAttempt),
          session: _config.session,
          pageUrl: _config.fieldsPageUrl,
          pageHeaders: _config.fieldsPageHeaders,
          wallet: wallet,
          returnUrl: _config.returnUrl,
          expectedInvoiceId: _config._invoiceToBind,
          ownSchemes: _config.ownSchemes,
          height: _walletChallenge
              ? _challengeHeightIn(context)
              : _config.style.rowHeight,
          onComplete: _onWalletResult,
          onCharging: _onWalletCharging,
          onChargingAfterLeaving: _onWalletChargingAfterLeaving,
          onUnavailable: _onWalletUnavailable,
          onChallenge: _onWalletChallenge,
        ),
      ),
    );
  }

  List<Widget> _selectCard() {
    return <Widget>[
      SheetHeader(
        style: _config.style,
        semanticLabel: _config.strings.back,
        onPressed: () => setState(() => _screen = _Screen.methods),
        isBack: true,
      ),
      SheetTitle(_config.strings.selectCard, style: _config.style),
      const SizedBox(height: 12),
      for (final card in _config.savedCards)
        MethodRow(
          style: _config.style,
          selected: card.id == _selected?.id,
          leading: BrandMark(brand: card.brand),
          title: '•••• ${card.last4}',
          subtitle: card.hasExpired ? _config.strings.expired : card.label,
          onTap: card.hasExpired
              ? null
              : () => setState(() {
                    _selected = card;
                    _screen = _Screen.methods;
                  }),
        ),
    ];
  }

  /// The card box with the whole sheet to itself, while the issuer's challenge is up.
  ///
  /// The SDK frames that challenge inside the box and it has to stay framed exactly that
  /// way, so nothing is drawn over it and nothing around it can take the tap that answers
  /// it. The close control sits above it, not over it: an issuer's page can stall, and a
  /// sheet that refuses Back, a tap outside and a drag would otherwise have no way out.
  List<Widget> _challenge(BuildContext context) {
    return <Widget>[
      SizedBox(
        height: _closeRowHeight,
        child: SheetHeader(
          style: _config.style,
          semanticLabel: _config.strings.close,
          onPressed: _closeByPayer,
        ),
      ),
      SizedBox(
        height: _challengeHeightIn(context),
        child: CardBox(controller: _card, style: _config.style),
      ),
    ];
  }

  /// How tall the challenge can be drawn without pushing the sheet off the screen.
  ///
  /// The issuer's page asks for a code, so the keyboard comes up and takes most of a short
  /// phone with it. The room left is therefore the ceiling: what the whole sheet may take,
  /// less the padding and the close row above the box, so the sheet never has to scroll the
  /// issuer's page. The share of the screen is what it settles on when there is more room
  /// than that.
  double _challengeHeightIn(BuildContext context) {
    final media = MediaQuery.of(context);
    final room = _tallestIn(context) - _contentPadding.top - _closeRowHeight;
    final wanted = media.size.height * _challengeShareOfScreen;

    return math.max(math.min(wanted, room), 0);
  }

  /// The last thing the payer sees: that it worked, and what for.
  List<Widget> _done() {
    return <Widget>[
      const SizedBox(height: 24),
      PaidMark(style: _config.style),
      const SizedBox(height: 16),
      Center(
        child:
            SheetTitle(_config.strings.paymentComplete, style: _config.style),
      ),
      if (_amountLabel.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _amountLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _config.style.mutedText),
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  /// The card screen's header: back to the methods, or a close while its charge runs.
  ///
  /// Going back mid-charge would put the saved card and the wallet in front of a payer whose
  /// card is still being charged, and a second payment one tap away.
  SheetHeader _cardScreenHeader() {
    if (_isSettling) {
      return SheetHeader(
        style: _config.style,
        semanticLabel: _config.strings.close,
        onPressed: _closeByPayer,
      );
    }

    return SheetHeader(
      style: _config.style,
      semanticLabel: _config.strings.back,
      onPressed: () => setState(() => _screen = _Screen.methods),
      isBack: true,
    );
  }

  List<Widget> _newCard() {
    return <Widget>[
      _cardScreenHeader(),
      SheetTitle(_config.strings.addNewCard, style: _config.style),
      const SizedBox(height: 16),
      SectionLabel(_config.strings.cardInformation, style: _config.style),
      SizedBox(
        height: _cardBoxHeight,
        child: CardBox(controller: _card, style: _config.style),
      ),
      if (_config.collectBillingAddress) ...<Widget>[
        const SizedBox(height: 16),
        SectionLabel(_config.strings.billingAddress, style: _config.style),
        BillingForm(
          fields: _billing,
          style: _config.style,
          strings: _config.strings,
          countries: _config.billingCountries,
          onChanged: () => setState(() {}),
        ),
      ],
      if (_card.errorMessage != null || _error != null)
        ErrorText(_card.errorMessage ?? _error!, style: _config.style),
      const SizedBox(height: 16),
      PayButton(
        label: '${_config.strings.pay} $_amountLabel'.trim(),
        style: _config.style,
        busy: _card.isCharging,
        onPressed: _canPayByCard ? _payByCard : null,
      ),
    ];
  }

  /// Exactly as tall as the rows the page is drawing, plus the box's own border.
  ///
  /// The web view is given a height rather than finding one, so the two have to agree: a
  /// box told to be shorter than its rows clips the last of them, and one told to be taller
  /// leaves a gap under the card that looks like a missing field.
  double get _cardBoxHeight {
    final rows =
        (_config.collectBillingAddress ? 3 : 2) + (_config.keepTheCard ? 1 : 0);

    return _config.style.rowHeight * rows + _boxBorders(rows) + _consentGrowth;
  }

  /// What the consent row needs beyond the row the box was drawn for.
  ///
  /// Every other row is the height the sheet asked for. This one is PayLink's, framed and
  /// worded by them, and in some languages it wraps to a second line. The box is a fixed
  /// height around a web view, so a row that grew without the box growing with it would
  /// have its tick below the fold, with the pay button refusing and nothing on screen
  /// saying why. Zero until the page says, and zero for a box with no such row.
  double get _consentGrowth {
    if (!_config.keepTheCard) {
      return 0;
    }

    final grown = _card.consentHeight - _config.style.rowHeight;

    return grown > 0 ? grown : 0;
  }

  /// Every hairline the box draws: one between each pair of rows, and its own two edges.
  ///
  /// Counted rather than rounded up, because the web view is given this height instead of
  /// finding one: a pixel short and the box's bottom edge is cropped off, which reads as a
  /// card form that ran out of room rather than as a box that is one pixel small.
  double _boxBorders(int rows) => (rows - 1) + 2;

  /// Whether there is enough on the card screen to charge, with nothing else in flight.
  ///
  /// The box answers for the card. The address is asked separately because the gateway
  /// ignores an incomplete one outright, and a payer who filled in half a billing form and
  /// was charged without it would never learn why their bank's address check failed.
  bool get _canPayByCard {
    if (_isSettling || !_card.isComplete) {
      return false;
    }

    if (_config.keepTheCard && !_card.snapshot.hasConsent) {
      return false;
    }

    return !_config.collectBillingAddress ||
        _billing.detailsFor(_card.snapshot.cardholderName).isComplete;
  }

  /// Charges the card in the box, billed to the address beside it.
  ///
  /// What the last attempt said is cleared first: left up during the next charge, it reads
  /// as that charge failing, and a payer who believes it closes the sheet mid-charge.
  Future<void> _payByCard() {
    if (_error != null) {
      setState(() => _error = null);
    }

    return _card.pay(
      billing: _config.collectBillingAddress
          ? _billing.detailsFor(_card.snapshot.cardholderName)
          : null,
    );
  }
}
