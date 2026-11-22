import '../core/validate.dart';
import '../errors.dart';

/// What the checkout view loads, or why it cannot.
class CheckoutSource {
  /// Creates a source for one checkout.
  const CheckoutSource({
    required this.uri,
    required this.returnUrl,
    this.expectedInvoiceId,
    this.error,
  });

  /// The URL the web view loads, or `about:blank` when the checkout cannot be shown.
  final String uri;

  /// The link that ends this checkout, as validated.
  final String returnUrl;

  /// The invoice id as it will be compared, already validated and normalised.
  final String? expectedInvoiceId;

  /// Why the checkout cannot load, for the developer.
  ///
  /// It names the option and the value it got, so it belongs in a log and never on a
  /// payment screen: the payer is shown `loadErrorMessage` instead, in the app's language.
  final String? error;
}

/// Validates the checkout view's inputs once per checkout, as a value rather than as a
/// thrown error.
///
/// An unusable `checkoutUrl`, `returnUrl` or `expectedInvoiceId` gives `about:blank` and an
/// [CheckoutSource.error] the view reports through its `onLoadError`. They arrive from a
/// server at runtime, and a bad one should not take the screen down with it.
///
/// The normalised invoice id is handed back, so the value the navigation handler compares
/// against is the one that was validated rather than the raw input.
CheckoutSource buildCheckoutSource(
  String checkoutUrl,
  String returnUrl,
  Object? expectedInvoiceId,
) {
  try {
    final invoiceId = assertExpectedInvoiceId(expectedInvoiceId);

    return CheckoutSource(
      uri: assertCheckoutUrl(checkoutUrl),
      returnUrl: assertReturnUrl(returnUrl),
      expectedInvoiceId: invoiceId,
    );
  } on GetPayInCheckoutError catch (cause) {
    return CheckoutSource(
        uri: 'about:blank', returnUrl: returnUrl, error: cause.message);
  }
}
