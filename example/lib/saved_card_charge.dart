import 'package:getpayin_checkout/getpayin_checkout.dart';

/// What the harness's server answered to a saved-card charge that is not asking for the
/// issuer.
///
/// Only PayLink's own `success` says how it went. The HTTP status cannot: PayLink answers a
/// charge that needs the issuer with a 202 that is not a payment, and this harness's server
/// answers anything that is not a charge or a challenge with a 422, an answer with no
/// `success` in it included. `success: true` is a charge and
/// `success: false` is a decline, with the reason PayLink gave, so the sheet offers another
/// try. Anything else may have come after the card was charged — PayLink records the payment
/// after the gateway answers, and a failure there is a server error with no `success` in
/// it — so it is reported as a payment nobody can confirm, never as a decline.
///
/// A charge that went through names the invoice it made and that invoice's paid status.
/// Both go on the result, so the sheet holds it to the same rule as any other claim of
/// payment and your app knows which invoice to read. A charge that names neither cannot be
/// held to that rule, so it is not reported as paid either.
CheckoutResult readSavedCardCharge(Map<String, Object?> body) {
  final success = body['success'];

  if (success == false) {
    return CheckoutResult(
      status: CheckoutStatus.notPaid,
      message: '${body['message'] ?? 'The saved card could not be charged.'}',
    );
  }

  final data = body['data'];
  final invoice =
      data is Map<String, Object?> ? data : const <String, Object?>{};
  final invoiceId = invoice['invoice_id'];
  final invoiceStatus = invoice['paid_status'];

  if (success != true || invoiceId == null || invoiceStatus == null) {
    return unconfirmedSavedCardCharge();
  }

  return CheckoutResult(
    status: CheckoutStatus.paid,
    invoiceId: '$invoiceId',
    invoiceStatus: '$invoiceStatus',
    message: 'Charged the saved card.',
  );
}

/// What the bank check on a saved-card charge settled with.
///
/// The harness's server answers a bank check it cannot vouch for — PayLink failed, or did
/// not answer, after the payer passed it — with a return link that carries no result, so
/// the sheet closes rather than offering another try. The package reads that as
/// unreadable, its code for a link it cannot parse. From this server it means nobody knows
/// how the charge ended, so it is reported as that. Every other result stands.
CheckoutResult readSavedCardChallenge(CheckoutResult result) {
  return result.code == CheckoutResultCode.unreadableReturnLink
      ? unconfirmedSavedCardCharge()
      : result;
}

/// A saved-card charge nobody can confirm, because it may have gone through.
CheckoutResult unconfirmedSavedCardCharge() {
  return CheckoutResult(
    status: CheckoutStatus.notPaid,
    code: CheckoutResultCode.outcomeUnknown,
    message: const PaymentSheetStrings().outcomeUnknown,
  );
}
