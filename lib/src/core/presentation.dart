import '../types.dart';

/// Decides where the checkout is drawn.
///
/// iOS always uses the app's own screen, where Apple Pay works. Android uses the app's own
/// screen only when the client has turned on [googlePayInApp], which is valid once Google
/// has approved their app; before that the browser sheet offers Google Pay with no approval
/// needed. Anything else — a desktop or web build the same code happens to run in — falls
/// back to the browser sheet.
///
/// [platform] is the plain name of the platform (`ios`, `android`), so the rule can be
/// tested without a phone and without Flutter's own platform lookup.
CheckoutPresentation resolvePresentation({
  required String platform,
  bool googlePayInApp = false,
  CheckoutPresentation? override,
}) {
  if (override != null) {
    return override;
  }

  if (platform == 'ios') {
    return CheckoutPresentation.inApp;
  }

  if (platform == 'android') {
    return googlePayInApp
        ? CheckoutPresentation.inApp
        : CheckoutPresentation.browser;
  }

  return CheckoutPresentation.browser;
}
