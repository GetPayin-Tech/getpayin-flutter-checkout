/// The web view settings the wallets depend on.
///
/// Every one of these fails silently when it is wrong: the wallet button simply does not
/// appear, with nothing in the log to say why. They are decided here, per platform, so no
/// client has to copy them out of a document and no caller can pass something that turns a
/// wallet off.
class CheckoutWebViewSettings {
  /// Creates the settings for one platform.
  const CheckoutWebViewSettings({
    required this.javaScriptEnabled,
    this.paymentRequestEnabled = false,
    this.applePayEnabled = false,
  });

  /// Always true: the hosted checkout is a JavaScript application, and both wallets are
  /// JavaScript APIs.
  final bool javaScriptEnabled;

  /// Android only. `AndroidWebViewController.setPaymentRequestEnabled`, which is what lets
  /// the Payment Request API — and so Google Pay — run inside a web view at all. It is off
  /// by default in Android's WebView, and must be set before the page loads.
  ///
  /// The user agent is deliberately left alone, because Google checks it and requires it to
  /// end with `GOOGLE_PAY_SUPPORTED`.
  final bool paymentRequestEnabled;

  /// iOS only. Apple Pay works in a `WKWebView` only while the host app has added no
  /// scripts to the page: WebKit turns the payment APIs off in the presence of a user
  /// script, with no error.
  ///
  /// There is no switch to set for this. It is a promise the package keeps instead: no
  /// JavaScript channel is ever registered on the checkout web view, and
  /// `runJavaScript` is never called on it — not anywhere, not even for diagnostics.
  final bool applePayEnabled;

  @override
  bool operator ==(Object other) {
    return other is CheckoutWebViewSettings &&
        other.javaScriptEnabled == javaScriptEnabled &&
        other.paymentRequestEnabled == paymentRequestEnabled &&
        other.applePayEnabled == applePayEnabled;
  }

  @override
  int get hashCode =>
      Object.hash(javaScriptEnabled, paymentRequestEnabled, applePayEnabled);

  @override
  String toString() {
    return 'CheckoutWebViewSettings(javaScriptEnabled: $javaScriptEnabled, '
        'paymentRequestEnabled: $paymentRequestEnabled, applePayEnabled: $applePayEnabled)';
  }
}

/// Builds the platform settings for the checkout web view.
///
/// [platform] is the plain platform name (`ios`, `android`), so the rule can be tested
/// without a phone.
CheckoutWebViewSettings buildCheckoutWebViewSettings(String platform) {
  if (platform == 'ios') {
    return const CheckoutWebViewSettings(
        javaScriptEnabled: true, applePayEnabled: true);
  }

  if (platform == 'android') {
    return const CheckoutWebViewSettings(
        javaScriptEnabled: true, paymentRequestEnabled: true);
  }

  return const CheckoutWebViewSettings(javaScriptEnabled: true);
}
