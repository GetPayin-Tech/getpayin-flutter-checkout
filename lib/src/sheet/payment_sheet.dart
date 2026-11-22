import 'dart:async';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../checkout.dart';
import '../core/messages.dart';
import '../core/return_url.dart';
import '../platform.dart';
import '../types.dart';
import 'amount.dart';
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

  /// The invoice this payment is for, so a result naming another one is refused.
  final Object? expectedInvoiceId;

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
  /// a payment that saves a card all end with the payer paying rather than stuck.
  final bool fallBackToHostedCheckout;

  /// The hosted checkout this payment falls back to.
  OpenCheckoutOptions get hostedOptions => OpenCheckoutOptions(
        returnUrl: returnUrl,
        expectedInvoiceId: expectedInvoiceId,
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
class GetPayInPaymentSheet extends StatefulWidget {
  /// Creates the sheet.
  const GetPayInPaymentSheet({required this.configuration, super.key});

  /// The payment this sheet is taking.
  final PaymentSheetConfiguration configuration;

  /// Presents the sheet and completes once the payment ends.
  ///
  /// The result is a report of what PayLink said, never proof of payment: confirm the
  /// `payment.*` webhook on your server before you deliver anything.
  static Future<CheckoutResult> show(
    BuildContext context,
    PaymentSheetConfiguration configuration,
  ) async {
    final outcome = await showModalBottomSheet<_SheetOutcome>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      barrierColor: const Color(0x66000000),
      builder: (_) => GetPayInPaymentSheet(configuration: configuration),
    );

    return switch (outcome) {
      _Settled(:final result) => result,
      _Fallback() => GetPayInCheckout.open(
          configuration.session.checkoutUrl,
          configuration.hostedOptions,
        ),
      null => cancelledResult(closedByPayerMessage),
    };
  }

  @override
  State<GetPayInPaymentSheet> createState() => _GetPayInPaymentSheetState();
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
  const _Fallback();
}

enum _Screen { methods, selectCard, newCard }

/// How tall the card box grows for a 3-D Secure challenge.
///
/// The issuer's page is a page, not a row: it carries its own instructions, a one-time code
/// field and a submit button, and a box sized for a card number would scroll all three.
const double _challengeHeight = 480;

class _GetPayInPaymentSheetState extends State<GetPayInPaymentSheet> {
  late final PaymentSheetConfiguration _config = widget.configuration;

  /// Built as the sheet opens rather than when the payer asks for it: the box has a page to
  /// load and fields to mount, and doing that behind the first screen is the difference
  /// between a card form that is there and one that arrives.
  late final CardFieldsController _card = CardFieldsController(
    session: _config.session,
    pageUrl: _config.fieldsPageUrl,
    style: _config.style,
    onPayment: _onPayment,
    onFailure: _onFieldsFailure,
  );

  _Screen _screen = _Screen.methods;
  SavedCard? _selected;
  bool _charging = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected =
        _config.savedCards.where((card) => !card.hasExpired).firstOrNull;
    _card.addListener(_onCardChanged);
  }

  @override
  void dispose() {
    _card.removeListener(_onCardChanged);
    _card.dispose();
    super.dispose();
  }

  void _onCardChanged() => setState(() {});

  void _onPayment(FieldsPayment payment) {
    _settle(resultFromPayment(payment,
        expectedInvoiceId: _config.expectedInvoiceId));
  }

  void _onFieldsFailure(FieldsError error) {
    if (!error.failure.sendsPayerToHostedCheckout) {
      setState(() {
        _charging = false;
        _error = error.message ?? _config.strings.cardDeclined;
      });

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

    _close(const _Fallback());
  }

  void _settle(CheckoutResult result) {
    if (result.status == CheckoutStatus.notPaid && result.code == null) {
      setState(() {
        _charging = false;
        _error = result.message ?? _config.strings.cardDeclined;
      });

      return;
    }

    _close(_Settled(result));
  }

  void _close(_SheetOutcome outcome) {
    if (mounted) {
      Navigator.of(context).pop(outcome);
    }
  }

  Future<void> _paySaved() async {
    final card = _selected;
    final charge = _config.chargeSavedCard;

    if (card == null || charge == null || _charging) {
      return;
    }

    setState(() {
      _charging = true;
      _error = null;
    });

    _settle(await charge(card));
  }

  String get _amountLabel {
    final minor = _card.amountMinor;
    final currency = _card.currency;

    if (minor != null && currency != null && currency.isNotEmpty) {
      return formatAmount(minor, currency);
    }

    return _config.amountLabel ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final style = _config.style;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _screenContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _screenContent() {
    return switch (_screen) {
      _Screen.methods => _methods(),
      _Screen.selectCard => _selectCard(),
      _Screen.newCard => _newCard(),
    };
  }

  List<Widget> _methods() {
    final strings = _config.strings;
    final wallet =
        PaymentWallet.forPlatform(currentPlatformName(), _config.wallets);
    final saved = _config.savedCards;

    return <Widget>[
      SheetHeader(
        style: _config.style,
        semanticLabel: strings.close,
        onPressed: () =>
            _close(_Settled(cancelledResult(closedByPayerMessage))),
      ),
      if (wallet != null) ...<Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(_config.style.radius),
          child: WalletSurface(
            session: _config.session,
            pageUrl: _config.fieldsPageUrl,
            wallet: wallet,
            returnUrl: _config.returnUrl,
            expectedInvoiceId: _config.expectedInvoiceId,
            ownSchemes: _config.ownSchemes,
            onComplete: _settle,
          ),
        ),
        const SizedBox(height: 16),
        OrDivider(label: strings.orPayUsing, style: _config.style),
        const SizedBox(height: 16),
      ],
      if (saved.isNotEmpty) ...<Widget>[
        SectionLabel(strings.saved, style: _config.style),
        MethodRow(
          style: _config.style,
          selected: true,
          leading: BrandMark(brand: _selected?.brand ?? CardBrand.unknown),
          title: '•••• ${_selected?.last4 ?? ''}',
          trailing: saved.length > 1
              ? LinkText(
                  strings.viewMore,
                  style: _config.style,
                  onTap: () => setState(() => _screen = _Screen.selectCard),
                )
              : null,
          onTap: saved.length > 1
              ? () => setState(() => _screen = _Screen.selectCard)
              : null,
        ),
        const SizedBox(height: 16),
      ],
      SectionLabel(strings.newPaymentMethod, style: _config.style),
      MethodRow(
        style: _config.style,
        leading: Icon(Icons.credit_card, size: 20, color: _config.style.text),
        title: strings.newCard,
        onTap: () => setState(() => _screen = _Screen.newCard),
      ),
      if (_error != null) ErrorText(_error!, style: _config.style),
      const SizedBox(height: 16),
      PayButton(
        label: '${_config.strings.pay} $_amountLabel'.trim(),
        style: _config.style,
        busy: _charging,
        onPressed: _selected != null && _config.chargeSavedCard != null
            ? _paySaved
            : null,
      ),
    ];
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
  /// it.
  List<Widget> _challenge() {
    return <Widget>[
      SizedBox(
        height: _challengeHeight,
        child: CardBox(controller: _card, style: _config.style),
      ),
    ];
  }

  List<Widget> _newCard() {
    if (_card.isAuthenticating) {
      return _challenge();
    }

    return <Widget>[
      SheetHeader(
        style: _config.style,
        semanticLabel: _config.strings.back,
        onPressed: () => setState(() => _screen = _Screen.methods),
        isBack: true,
      ),
      SheetTitle(_config.strings.addNewCard, style: _config.style),
      const SizedBox(height: 16),
      SectionLabel(_config.strings.cardInformation, style: _config.style),
      SizedBox(
          height: 98, child: CardBox(controller: _card, style: _config.style)),
      if (_card.errorMessage != null || _error != null)
        ErrorText(_card.errorMessage ?? _error!, style: _config.style),
      const SizedBox(height: 16),
      PayButton(
        label: '${_config.strings.pay} $_amountLabel'.trim(),
        style: _config.style,
        busy: _card.isCharging,
        onPressed: _card.isComplete ? _card.pay : null,
      ),
    ];
  }
}
