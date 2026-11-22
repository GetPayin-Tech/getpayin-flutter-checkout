import '../types.dart';
import 'invoice_id.dart';
import 'url.dart';

/*
 * The fields of GetPayIn's return link, as the backend's app-return bridge builds it:
 *
 *   myapp://payment-return?success=1&invoice_id=4512&invoice_status=PAID&message=…&signature=…
 *
 * `success` is `1` or `0`. Only `success`, `invoice_id`, `invoice_status` and `message` are
 * read. A reader that also accepted other names (`status`, `state`, `result`, …) would let
 * a field the backend adds later decide the outcome without anyone noticing.
 *
 * The names must match exactly and the values are taken as sent. A link that repeats any
 * field, or that carries a name only a looser reader would take for one of these four —
 * `Success`, `invoiceId`, `%73uccess` — is unreadable. That keeps this reader and a server
 * that checks the link's `signature` from ever reading different values out of the same
 * link: a looser reader (any case, first copy wins) could report invoice B as paid from a
 * link whose signature is genuine for invoice A. None of this stops a forged link from
 * saying `success=1`; that is what the `invoice.paid` webhook on the server is for.
 */

const String _successKey = 'success';
const String _invoiceKey = 'invoice_id';
const String _invoiceStatusKey = 'invoice_status';
const String _messageKey = 'message';

/// The only four field names this reader takes any notice of.
const Set<String> _readKeys = <String>{
  _successKey,
  _invoiceKey,
  _invoiceStatusKey,
  _messageKey,
};

/// The read keys with case and separators collapsed, for spotting a name that is not one
/// of them but that another reader of the same link could take for one.
final Set<String> _readTokens = _readKeys.map(normalizeToken).toSet();

/// The one `invoice_status` that means the invoice is settled in full.
///
/// `UNPAID`, `PARTIALLY_PAID` and `AUTHORIZED` are not orders to fulfil, so a link carrying
/// one of them is reported as not paid however its `success` flag reads.
const Set<String> _paidInvoiceStatuses = <String>{'paid'};

const String _unreadableMessage =
    'The checkout returned without a status this package recognises. Confirm the invoice on '
    'your server before you treat it as paid.';

const String _wrongInvoiceMessage =
    'The return link named a different invoice from the one this checkout was opened for, '
    "so it is not this checkout's result.";

const String _unexpectedStatusMessage =
    'The checkout reported the invoice as something other than paid in full. Confirm it on '
    'your server before you treat it as paid.';

/// True when [url] is the return link the checkout was opened with.
bool matchesReturnUrl(String url, String returnUrl) {
  return isSameTarget(url, returnUrl);
}

/// The single value of [key], or null when it is absent or empty.
String? _readField(Map<String, List<String>> params, String key) {
  final value = params[key]?.first;

  return value == null || value.isEmpty ? null : value;
}

/// The link's own message, with blank text treated as no message at all.
String? _readMessage(Map<String, List<String>> params) {
  final value = _readField(params, _messageKey);

  return value == null || value.trim().isEmpty ? null : value;
}

/// True when the link repeats any field.
///
/// Every field, not only the four that are read: a repeated `signature` is how a server
/// that checks it and this reader could be made to disagree about which copy of the link
/// they are looking at.
bool _repeatsAField(Map<String, List<String>> params) {
  return params.values.any((values) => values.length > 1);
}

/// True when a field name is not one of the four read, yet collapses onto one of them.
///
/// `Success`, `INVOICE_ID`, `invoiceId` and `%73uccess` all reach a reader that folds case,
/// ignores separators or decodes names before matching. A server verifying the signature
/// over the raw query string would not see them as those fields, so the link is refused
/// rather than read one way here and another way there.
bool _hasAmbiguousName(List<String> names) {
  return names.any(
    (name) =>
        !_readKeys.contains(name) &&
        (_readTokens.contains(normalizeToken(name)) ||
            _readTokens.contains(normalizeToken(decodeQueryComponent(name)))),
  );
}

/// Maps GetPayIn's `success` flag onto an outcome; anything but `1` or `0` is unreadable.
CheckoutStatus? _readStatus(String? success) {
  if (success == '1') {
    return CheckoutStatus.paid;
  }

  if (success == '0') {
    return CheckoutStatus.notPaid;
  }

  return null;
}

/// The result for a link whose own fields could not be read.
///
/// The link's own `message` is dropped rather than shown. GetPayIn's bridge always sends
/// one, so keeping it would make this indistinguishable from a genuine decline — and a link
/// reading `success=true&message=Payment+completed` would tell the payer the payment
/// succeeded while the app was told it had not. [CheckoutResult.code] is what an app
/// branches on.
CheckoutResult _unreadableResult(String url) {
  return CheckoutResult(
    status: CheckoutStatus.notPaid,
    code: CheckoutResultCode.unreadableReturnLink,
    message: _unreadableMessage,
    returnUrl: url,
  );
}

/// Refuses a paid result whose `invoice_status` is not `PAID`.
///
/// Only a downgrade, never an upgrade: a `success=0` carrying `invoice_status=PAID` stays
/// not paid. A link with no `invoice_status` at all is left as it was, so a backend that
/// stops sending the field does not turn every payment into a failure.
CheckoutResult _bindToInvoiceStatus(CheckoutResult result) {
  final invoiceStatus = result.invoiceStatus;

  if (result.status != CheckoutStatus.paid || invoiceStatus == null) {
    return result;
  }

  if (_paidInvoiceStatuses.contains(normalizeToken(invoiceStatus))) {
    return result;
  }

  return result.downgradedTo(
    CheckoutStatus.notPaid,
    code: CheckoutResultCode.unexpectedInvoiceStatus,
    message: _unexpectedStatusMessage,
  );
}

/// Turns a return link into a result.
///
/// A link whose status cannot be read becomes not paid with an explanatory message and
/// [CheckoutResultCode.unreadableReturnLink], never paid: the app is not allowed to decide
/// that a payment succeeded, and the `invoice.paid` webhook on your server is what settles
/// it either way.
CheckoutResult readCheckoutResult(String url) {
  final query = parseUrl(url)?.query ?? '';
  final params = readQuery(query);

  if (_repeatsAField(params) || _hasAmbiguousName(rawQueryNames(query))) {
    return _unreadableResult(url);
  }

  final status = _readStatus(_readField(params, _successKey));

  if (status == null) {
    return _unreadableResult(url);
  }

  return _bindToInvoiceStatus(
    CheckoutResult(
      status: status,
      invoiceId: _readField(params, _invoiceKey),
      invoiceStatus: _readField(params, _invoiceStatusKey),
      message: _readMessage(params),
      returnUrl: url,
    ),
  );
}

/// Refuses a paid result that does not belong to the invoice the checkout was opened for.
///
/// Only a paid result is downgraded. A not-paid or cancelled one carries no claim worth
/// checking, and rewriting it would lose the reason the payer was given.
///
/// Both sides go through [invoiceIdFrom] and [normalizeInvoiceId], so a number from the
/// server and the text in the link are compared in one form. Only null means no invoice to
/// bind to; anything the validator would refuse — `''`, `true`, a non-finite or fractional
/// `double`, a `Map` — binds to nothing, so a paid result is refused. `open()` and the view
/// reject those values up front (`assertExpectedInvoiceId`); this is the fail-closed
/// backstop for callers of the lower-level exports, and it refuses exactly what the
/// validator refuses.
CheckoutResult _bindToInvoice(
    CheckoutResult result, Object? expectedInvoiceId) {
  if (expectedInvoiceId == null || result.status != CheckoutStatus.paid) {
    return result;
  }

  final expected = invoiceIdFrom(expectedInvoiceId);
  final claimed = result.invoiceId;
  final reported = claimed == null ? null : normalizeInvoiceId(claimed);

  if (expected != null && reported == expected) {
    return result;
  }

  return result.downgradedTo(
    CheckoutStatus.notPaid,
    code: CheckoutResultCode.wrongInvoice,
    message: _wrongInvoiceMessage,
  );
}

/// Turns a return link into a result, bound to the checkout it was opened for.
///
/// Both presentations go through this, so the in-app screen and the browser sheet cannot
/// drift apart on what a given link means.
CheckoutResult resolveReturn(String url, {Object? expectedInvoiceId}) {
  return _bindToInvoice(readCheckoutResult(url), expectedInvoiceId);
}

/// The result for a payer who closed the checkout without finishing.
CheckoutResult cancelledResult([String? message]) {
  return CheckoutResult(status: CheckoutStatus.cancelled, message: message);
}
