import 'core/invoice_id.dart';
import 'core/return_url.dart';
import 'core/url.dart';
import 'types.dart';

/// How a card save ended.
enum CardSaveStatus {
  /// The card was vaulted. The token is on your server, not here.
  saved('saved'),

  /// The card was not vaulted, or the link could not be trusted to say it was.
  notSaved('not_saved'),

  /// The payer closed the screen without finishing.
  cancelled('cancelled');

  const CardSaveStatus(this.wireName);

  /// The stable text form, for logs.
  final String wireName;
}

/// What a finished card save hands back.
///
/// A tokenization run is not a payment: PayLink authorizes one unit of currency to prove the
/// card is live, vaults it, and releases the authorization straight away. So the invoice it
/// runs against is *meant* to end unpaid, and reading it with the payment rules would report
/// every successful save as a failure.
///
/// This is still only a report of what the return link said. **The token is never on it**:
/// the app-return bridge carries `success`, `invoice_id`, `invoice_status`, `message` and
/// `signature`, and nothing else. The card token reaches you on the `card_token.created`
/// webhook, which is also what tells you the save is real.
class CardSaveResult {
  /// Creates a card save result.
  const CardSaveResult({
    required this.status,
    this.invoiceId,
    this.verificationStatus,
    this.code,
    this.message,
    this.returnUrl,
  });

  /// How the save ended.
  final CardSaveStatus status;

  /// The verification invoice the run went against, when the link named one.
  final String? invoiceId;

  /// What the link reported as the state of that verification.
  ///
  /// `AUTHORIZED` while the one-unit hold stands, `VOIDED` once it is released, `CAPTURED`
  /// if it was taken. None of them is a failure of the save, and none of them is `PAID`.
  final String? verificationStatus;

  /// Why this is not a save, when the reason is worth branching on.
  ///
  /// Only [CheckoutResultCode.unreadableReturnLink] and [CheckoutResultCode.wrongInvoice]
  /// can appear. A card the gateway refused carries no code, exactly as a declined payment
  /// does not.
  final CheckoutResultCode? code;

  /// Text for the payer, in the language the checkout produced it in.
  final String? message;

  /// The return link this was read from, when there was one.
  final String? returnUrl;

  /// True when the card was vaulted.
  ///
  /// Still not the token, and still not proof: wait for `card_token.created`.
  bool get isSaved => status == CardSaveStatus.saved;

  @override
  String toString() {
    return 'CardSaveResult(status: ${status.wireName}, invoiceId: $invoiceId, '
        'verificationStatus: $verificationStatus, code: ${code?.wireName})';
  }
}

const String _unreadableMessage =
    'The card save returned without a status this package recognises. Check the card on '
    'your server before you offer it to the payer again.';

const String _wrongInvoiceMessage =
    'The return link named a different verification from the one this card save was opened '
    "for, so it is not this run's result.";

/// Reads a tokenization run's return link.
///
/// The link is read by the same strict rules a payment's is — exact field names, values as
/// sent, and a link that repeats a field or carries a name only a looser reader would take
/// for one of them is refused — because it is the same link, signed the same way. What
/// differs is only what a success is allowed to mean: here the invoice is expected to end
/// unpaid, so the state of the verification is reported rather than held against it.
CardSaveResult readCardSave(String url, {Object? expectedInvoiceId}) {
  final claim = readReturnClaim(url);

  if (claim.code == CheckoutResultCode.unreadableReturnLink) {
    return CardSaveResult(
      status: CardSaveStatus.notSaved,
      code: CheckoutResultCode.unreadableReturnLink,
      message: _unreadableMessage,
      returnUrl: url,
    );
  }

  final save = CardSaveResult(
    status: claim.status == CheckoutStatus.paid
        ? CardSaveStatus.saved
        : CardSaveStatus.notSaved,
    invoiceId: claim.invoiceId,
    verificationStatus: claim.invoiceStatus,
    message: claim.message,
    returnUrl: url,
  );

  if (save.status != CardSaveStatus.saved || expectedInvoiceId == null) {
    return save;
  }

  if (invoiceIdMatches(expected: expectedInvoiceId, reported: save.invoiceId)) {
    return save;
  }

  return CardSaveResult(
    status: CardSaveStatus.notSaved,
    invoiceId: save.invoiceId,
    verificationStatus: save.verificationStatus,
    code: CheckoutResultCode.wrongInvoice,
    message: _wrongInvoiceMessage,
    returnUrl: url,
  );
}

/// Reads a card save out of the checkout the package already ran.
///
/// Both presentations hand back a [CheckoutResult] carrying the raw return link, so the save
/// is read off that link rather than off the payment verdict: a payment reader has already
/// decided that an unpaid invoice is not a success, which for a verification run is exactly
/// backwards.
CardSaveResult cardSaveFromCheckout(CheckoutResult checkout,
    {Object? expectedInvoiceId}) {
  if (checkout.status == CheckoutStatus.cancelled) {
    return CardSaveResult(
        status: CardSaveStatus.cancelled, message: checkout.message);
  }

  final link = checkout.returnUrl;

  if (link == null) {
    return CardSaveResult(
      status: CardSaveStatus.notSaved,
      code: CheckoutResultCode.unreadableReturnLink,
      message: checkout.message ?? _unreadableMessage,
    );
  }

  return readCardSave(link, expectedInvoiceId: expectedInvoiceId);
}

/// The invoice id a hosted URL names, so a run can be bound to the one it opened.
///
/// `POST /v2/integration/tokens/init` hands back a `tokenization_url` rather than an invoice
/// id, and `/init` hands back both. Reading it off the URL is what lets a card save pass
/// `expectedInvoiceId` and so refuse a return link that names another run.
String? invoiceIdInCheckoutUrl(String url) {
  final value = readQuery(parseUrl(url)?.query ?? '')['invoice_id']?.first;

  return value == null || value.trim().isEmpty ? null : value.trim();
}
