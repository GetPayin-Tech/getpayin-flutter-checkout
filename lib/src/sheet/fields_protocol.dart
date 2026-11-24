import 'dart:convert';

import '../core/return_url.dart';
import '../types.dart';
import 'billing_details.dart';
import 'fields_session.dart';

/// What the fields page reports while the payer is on it.
///
/// The page runs PayLink's own SDK and forwards its events; this is the Dart side of that
/// one channel. Parsing lives here, with no widget behind it, because what the sheet shows
/// and what it finally reports are decided by these messages.
sealed class FieldsEvent {
  const FieldsEvent();
}

/// The fields are live, and the gateway has said what will actually be charged.
class FieldsReady extends FieldsEvent {
  /// Creates the ready event.
  const FieldsReady({required this.amountMinor, required this.currency});

  /// What will be charged, in the currency's minor units, after any conversion.
  final int amountMinor;

  /// The currency it will be charged in.
  final String currency;
}

/// One hosted field changed, so the sheet can show its own validation.
class FieldsChanged extends FieldsEvent {
  /// Creates the change event.
  const FieldsChanged({
    required this.field,
    required this.valid,
    required this.empty,
    required this.couldBeValid,
    this.value,
  });

  /// `number`, `securityCode`, `expiry` or `name`.
  final String field;

  /// Whether what the payer has typed is a usable value.
  final bool valid;

  /// Whether the field is empty.
  final bool empty;

  /// Whether it could still become valid as the payer keeps typing.
  final bool couldBeValid;

  /// What the payer typed, for the inputs the gateway does not host.
  ///
  /// Null for the card number and the security code, and it must stay null for them: those
  /// are rendered inside the gateway's own frames precisely so that nothing on this side of
  /// the channel ever sees them. The name on the card is not cardholder data in that sense,
  /// and the sheet needs it to bill the charge to someone.
  final String? value;
}

/// 3-D Secure started.
///
/// In two stages, and the sheet owes the payer something different in each. `setup` is the
/// gateway talking to the issuer with nothing to show for it; `challenge` is the issuer
/// asking the payer a question, framed by the SDK inside the box, which then needs the
/// whole screen. Treating the first like the second strands the payer on a card form that
/// has stopped responding.
class FieldsAuthenticating extends FieldsEvent {
  /// Creates the authenticating event.
  const FieldsAuthenticating({this.stage = 'setup'});

  /// `setup` or `challenge`.
  final String stage;

  /// True once the issuer is asking the payer something.
  bool get isChallenge => stage == 'challenge';
}

/// The charge is running and can no longer be cancelled.
class FieldsCharging extends FieldsEvent {
  /// Creates the charging event.
  const FieldsCharging();
}

/// The charge answered, either way. A decline is an answer, not a failure.
class FieldsPayment extends FieldsEvent {
  /// Creates the payment event.
  const FieldsPayment({
    required this.success,
    this.message,
    this.reasonCode,
    this.invoiceId,
    this.paidStatus,
    this.returnUrl,
  });

  /// Whether the charge was approved.
  final bool success;

  /// Text for the payer, as PayLink worded it.
  final String? message;

  /// The gateway's reason code, for a log.
  final String? reasonCode;

  /// The invoice the charge was booked against.
  final Object? invoiceId;

  /// The invoice state afterwards: `PAID`, `UNPAID`, `AUTHORIZED`, and so on.
  final String? paidStatus;

  /// Where a browser would have been sent next.
  final String? returnUrl;
}

/// The attempt could not be completed.
class FieldsError extends FieldsEvent {
  /// Creates the error event.
  const FieldsError({required this.failure, this.message});

  /// What went wrong, and whether the payer has to go to the hosted checkout.
  final FieldsFailure failure;

  /// Text for the payer, when the page had any.
  final String? message;
}

/// The wallet button is rendered and can be tapped.
class FieldsWalletReady extends FieldsEvent {
  /// Creates the wallet-ready event.
  const FieldsWalletReady(this.paymentTypes);

  /// Which wallets the context offered, as PayLink named them.
  final List<String> paymentTypes;
}

/// The wallet could not load. The card fields are unaffected.
class FieldsWalletError extends FieldsEvent {
  /// Creates the wallet-error event.
  const FieldsWalletError({this.message});

  /// Text for a log. The payer is simply shown no wallet button.
  final String? message;
}

/// Reads one message from the fields page, or null when it is not one.
///
/// Never throws. The page is the only thing that posts here, but it posts over a channel a
/// page could in principle be navigated away from, and a malformed message must not take a
/// payment screen down: an unreadable message is no event at all.
FieldsEvent? parseFieldsEvent(String raw) {
  final Object? decoded;

  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }

  if (decoded is! Map<String, Object?>) {
    return null;
  }

  return switch (decoded['type']) {
    'ready' => FieldsReady(
        amountMinor: _intAt(decoded, 'amountMinor') ?? 0,
        currency: _stringAt(decoded, 'currency') ?? '',
      ),
    'change' => FieldsChanged(
        field: _stringAt(decoded, 'field') ?? '',
        valid: decoded['valid'] == true,
        empty: decoded['empty'] != false,
        couldBeValid: decoded['couldBeValid'] != false,
        value: _stringAt(decoded, 'value'),
      ),
    'authenticating' => FieldsAuthenticating(
        stage: _stringAt(decoded, 'stage') ?? 'setup',
      ),
    'charging' => const FieldsCharging(),
    'payment' => FieldsPayment(
        success: decoded['success'] == true,
        message: _stringAt(decoded, 'message'),
        reasonCode: _stringAt(decoded, 'reasonCode'),
        invoiceId: _scalarAt(decoded, 'invoiceId'),
        paidStatus: _stringAt(decoded, 'paidStatus'),
        returnUrl: _stringAt(decoded, 'returnUrl'),
      ),
    'error' => FieldsError(
        failure: FieldsFailure.fromCode(_stringAt(decoded, 'code')),
        message: _stringAt(decoded, 'message'),
      ),
    'walletready' => FieldsWalletReady(
        (decoded['paymentTypes'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
      ),
    'walleterror' => FieldsWalletError(message: _stringAt(decoded, 'message')),
    _ => null,
  };
}

/// Turns the charge PayLink reported into a result, by the rules every claim goes through.
///
/// Two sources can say an invoice was paid: the return link the hosted checkout comes back
/// with, and this message. They are read differently — one is a URL, the other is JSON — but
/// what a claim has to survive is the same, so both end at [settlePaidClaim]: only `PAID` is
/// paid, and a paid claim for another invoice is refused.
///
/// A link is preferred when the page handed one back that reads as GetPayIn's own return
/// link, because that is the same artefact a server checks the signature of.
CheckoutResult resultFromPayment(FieldsPayment payment,
    {Object? expectedInvoiceId}) {
  final link = payment.returnUrl;

  if (link != null) {
    final fromLink = readCheckoutResult(link);

    if (fromLink.code != CheckoutResultCode.unreadableReturnLink) {
      return settlePaidClaim(fromLink, expectedInvoiceId: expectedInvoiceId);
    }
  }

  final invoiceId = payment.invoiceId;

  return settlePaidClaim(
    CheckoutResult(
      status: payment.success ? CheckoutStatus.paid : CheckoutStatus.notPaid,
      invoiceId: invoiceId == null ? null : '$invoiceId',
      invoiceStatus: payment.paidStatus,
      message: payment.message,
      returnUrl: link,
    ),
    expectedInvoiceId: expectedInvoiceId,
  );
}

/// One line saying what the page reported, for a diagnostic someone will paste somewhere.
///
/// It says what happened and never what was typed. The card number and the security code
/// are the gateway's and never reach this side at all, but the name on the card does, and a
/// trace carrying a payer's name is one nobody can safely send anywhere. A failure is the
/// exception: its message is the whole reason the line exists, especially for a code this
/// package does not recognise.
String describeFieldsEvent(FieldsEvent event) {
  return switch (event) {
    FieldsReady(:final amountMinor, :final currency) =>
      'ready $amountMinor $currency',
    FieldsChanged(:final field, :final valid, :final empty) =>
      'change $field ${empty ? 'empty' : (valid ? 'valid' : 'incomplete')}',
    FieldsAuthenticating(:final stage) => 'authenticating $stage',
    FieldsCharging() => 'charging',
    FieldsPayment(
      :final success,
      :final message,
      :final reasonCode,
      :final invoiceId,
      :final paidStatus,
    ) =>
      'payment ${success ? 'approved' : 'declined'}'
          '${reasonCode == null ? '' : ' $reasonCode'}'
          '${invoiceId == null ? '' : ' invoice $invoiceId'}'
          '${paidStatus == null ? '' : ' $paidStatus'}'
          '${message == null ? '' : ': $message'}',
    FieldsError(:final failure, :final message) =>
      'error ${failure.wireName}${message == null ? '' : ': $message'}',
    FieldsWalletReady(:final paymentTypes) =>
      'wallet ready ${paymentTypes.join(',')}',
    FieldsWalletError(:final message) =>
      'wallet error${message == null ? '' : ': $message'}',
  };
}

/// The JavaScript that starts the fields, sent once the page has loaded.
///
/// The client token is handed over this way rather than in the page's URL: a URL reaches
/// the host's access log, the browser's history and any `Referer` the page sends, and a
/// token that names a payment has no business in any of them.
///
/// [sdkUrl] is where that payment's PayLink serves the SDK, as `/init` reported it. The
/// page is hosted once and a payment knows which PayLink it belongs to, so the host says
/// which one rather than the page deciding when it was generated — a page pinned to one
/// environment and a token minted on another fails with an error naming the wrong system.
String startFieldsCommand({
  required String clientToken,
  required Map<String, Object?> style,
  List<String> wallets = const <String>[],
  String? sdkUrl,
  bool collectName = false,
  bool collectConsent = false,
  String nameLabel = 'Name on card',
  String cardNumberLabel = 'Card number',
  String expiryLabel = 'MM / YY',
  String securityCodeLabel = 'CVC',
}) {
  final config = jsonEncode(<String, Object?>{
    'clientToken': clientToken,
    if (sdkUrl != null) 'sdkUrl': sdkUrl,
    'wallets': wallets,
    'style': style,
    'collectName': collectName,
    'collectConsent': collectConsent,
    'nameLabel': nameLabel,
    'cardNumberLabel': cardNumberLabel,
    'expiryLabel': expiryLabel,
    'securityCodeLabel': securityCodeLabel,
  });

  return 'window.__paylinkHost && window.__paylinkHost.start($config);';
}

/// The JavaScript that takes the fields down.
///
/// The page holds a mounted fields instance and the capture context behind it, so a box
/// that goes away without saying so leaves both running for as long as the web view lives.
String destroyCommand() =>
    'window.__paylinkHost && window.__paylinkHost.destroy();';

/// The JavaScript that charges the card the payer entered, billed to [billing].
///
/// It carries no expiry: the expiry input sits inside the card box with the two hosted
/// fields, because a box whose three inputs are drawn by two different engines cannot be
/// kept aligned, and an expiry date is not cardholder data for the page to be trusted with.
///
/// It does carry the address, for the opposite reason: the billing form is drawn by the
/// sheet, the gateway's token holds no address of its own, and the page has nothing to add
/// to one. Null for an address the charge would ignore, so the page is told the same thing
/// in both cases rather than having to decide.
String payCommand({BillingDetails? billing, bool keepTheCard = false}) {
  final wire = billing?.toWire() ?? const <String, Object?>{};
  final asked = <String, Object?>{
    if (wire.isNotEmpty) 'billing': wire,
    if (keepTheCard) 'tokenize': true,
  };

  final argument = asked.isEmpty ? 'null' : jsonEncode(asked);

  return 'window.__paylinkHost && window.__paylinkHost.pay($argument);';
}

String? _stringAt(Map<String, Object?> source, String key) {
  final value = source[key];

  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

int? _intAt(Map<String, Object?> source, String key) {
  final value = source[key];

  if (value is int) {
    return value;
  }

  return value is num ? value.toInt() : null;
}

Object? _scalarAt(Map<String, Object?> source, String key) {
  final value = source[key];

  return value is String || value is num ? value : null;
}
