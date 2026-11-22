import 'dart:convert';

import '../errors.dart';
import 'invoice_id.dart';
import 'url.dart';

/// Checks the checkout URL before anything is drawn, and hands back the trimmed value.
///
/// The trimmed value is what is returned because it is what was validated. The native side
/// does not trim, so a stray leading space would pass a check made on the trimmed string
/// and then fail inside the web view or the browser sheet, where the cause is invisible.
///
/// The usual cause of a bad value here is passing `checkout_url` through a route parameter,
/// which decodes it a second time and breaks the link's signature. Keep it in memory and
/// hand it straight to the package.
///
/// Throws [GetPayInConfigError] when the value is not an `http(s)` URL.
String assertCheckoutUrl(String checkoutUrl) {
  final trimmed = checkoutUrl.trim();
  final parsed = parseUrl(trimmed);

  if (parsed == null || (parsed.scheme != 'https' && parsed.scheme != 'http')) {
    throw GetPayInConfigError(
      'checkoutUrl must be an http(s) URL from your server; received "$checkoutUrl".',
    );
  }

  return trimmed;
}

/// Checks the return link the checkout is expected to come back to.
///
/// Throws [GetPayInConfigError] when the value does not start with a scheme.
String assertReturnUrl(String returnUrl) {
  final trimmed = returnUrl.trim();

  if (parseUrl(trimmed) == null) {
    throw GetPayInConfigError(
      'returnUrl must start with your app\'s scheme, for example "myapp://payment-return"; '
      'received "$returnUrl".',
    );
  }

  return trimmed;
}

/// Checks the invoice id a checkout is bound to, and hands back the text it is compared as.
///
/// The normalised value is what is returned, so the comparison inside `resolveReturn` is
/// made on what was validated rather than on the raw option: the server reports the id as a
/// number and the return link carries it as text, and comparing those as they arrive would
/// turn every paid checkout into a not-paid one.
///
/// Only null means "no invoice to bind to". Anything else that is not non-blank text or a
/// whole, finite number is refused — `''`, `true`, `double.nan`, `1e21`, `45.12`, a `Map`
/// such as the whole init response — because taking it as "not given" would quietly accept
/// a genuine paid link for any other invoice, and comparing against it would report every
/// real payment as not paid. A setup error shows the mistake while the app is being built
/// instead.
///
/// A field missing from your server's JSON arrives as null and cannot be told apart from
/// leaving the option out, so it is not caught here.
///
/// Throws [GetPayInConfigError] for a value that cannot be an invoice id.
String? assertExpectedInvoiceId(Object? expectedInvoiceId) {
  if (expectedInvoiceId == null) {
    return null;
  }

  final invoiceId = invoiceIdFrom(expectedInvoiceId);

  if (invoiceId != null) {
    return invoiceId;
  }

  throw GetPayInConfigError(
    'expectedInvoiceId must be the invoice_id your server received from init, as text or a '
    'whole number; received ${_describeValue(expectedInvoiceId)}. Leave it out only if you '
    'have no invoice id at all.',
  );
}

/// Names a bad value for an error message without serialising it (it may be circular).
String _describeValue(Object? value) {
  if (value is String) {
    return jsonEncode(value);
  }

  if (value is num || value is bool) {
    return value.toString();
  }

  return value is List ? 'a list' : 'a value of type ${value.runtimeType}';
}
