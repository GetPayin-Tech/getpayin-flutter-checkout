/*
 * One form for the invoice id, used by everything that compares two of them.
 *
 * The id reaches this package from two places that disagree about its type: `POST
 * /api/integration/init` reports it as a JSON number, while the return link carries it as
 * text. Reducing both sides here is what keeps a paid checkout from being reported as not
 * paid — and keeps the rule in one place, so the validator that refuses a bad value up
 * front and the backstop inside `resolveReturn` cannot drift apart on what counts as the
 * same invoice.
 */

/// Digits only, which is the shape GetPayIn's own invoice ids have.
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Leading zeros on a digits-only id, which carry no meaning.
final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

/// Past the point a floating-point number still holds every digit of an invoice id.
const int _maxExactInDouble = 9007199254740991;

/// Reduces one invoice id to the form the two sides are compared in.
///
/// Trimmed, because the link side arrives percent-decoded and `+` decodes to a space, so a
/// stray `invoice_id=+4512` would otherwise never match the `4512` the server reported.
/// Leading zeros are dropped from a digits-only id for the same reason: it is the same
/// invoice written two ways, and refusing it would tell a payer who has paid to pay again.
String normalizeInvoiceId(String value) {
  final trimmed = value.trim();

  return _digitsOnly.hasMatch(trimmed)
      ? trimmed.replaceFirst(_leadingZeros, '')
      : trimmed;
}

/// The invoice id a value can be bound to, or null when it cannot be one.
///
/// Text must be non-blank. An `int` is taken as written: Dart integers are exact, so the
/// digits the server sent are the digits compared. A `double` is only an invoice id when it
/// is finite, whole and small enough to still hold every digit — past that a value has
/// already lost digits by the time it gets here, so comparing it would report a real
/// payment as not paid for a reason invisible from the call site. Null, `NaN`, `true` and a
/// `Map` — the whole init response passed by untyped code — are all refused.
String? invoiceIdFrom(Object? value) {
  if (value is int) {
    return normalizeInvoiceId(value.toString());
  }

  if (value is double) {
    if (!value.isFinite || value != value.truncateToDouble()) {
      return null;
    }

    return value.abs() <= _maxExactInDouble
        ? normalizeInvoiceId(value.toInt().toString())
        : null;
  }

  if (value is String && value.trim().isNotEmpty) {
    return normalizeInvoiceId(value);
  }

  return null;
}

/// True when a run that reported [reported] belongs to the invoice [expected] names.
///
/// Fails closed: a value that cannot be an invoice id matches nothing, so a claim bound to
/// one is refused rather than taken at its word. Both sides go through [invoiceIdFrom] and
/// [normalizeInvoiceId], because the server reports the id as a number and the link carries
/// it as text.
bool invoiceIdMatches({required Object? expected, required String? reported}) {
  final wanted = invoiceIdFrom(expected);

  if (wanted == null || reported == null) {
    return false;
  }

  return normalizeInvoiceId(reported) == wanted;
}
