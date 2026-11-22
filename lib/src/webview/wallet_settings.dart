import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'platform_settings.dart';

/// Turns on a web view's wallet support, for the surfaces that show a wallet.
///
/// Separate from the surfaces themselves because every one of them needs it and none of
/// them can see whether it worked: Android's Payment Request switch is off by default, and
/// a page that asks for Google Pay without it is simply told there is no wallet. Both the
/// hosted checkout and the sheet's wallet button go through here, so neither can be built
/// without it.
typedef WalletSettingsApplier = Future<void> Function(
  WebViewController controller,
  CheckoutWebViewSettings settings,
);

/// The applier every surface uses. Replaceable in a test, like the other platform ports.
WalletSettingsApplier walletSettingsApplier = applyWalletSettings;

/// Turns on the platform's wallet support, if it has a switch and this build has it.
///
/// Must run before the page loads: Android reads the Payment Request switch at the next
/// load, so setting it afterwards gives the payer a surface with no wallet button and
/// nothing in the log.
///
/// A failure is swallowed rather than surfaced. An older web view that does not know the
/// feature still takes card payments, and the payer is better served by a checkout with no
/// wallet button than by an error instead of a checkout.
Future<void> applyWalletSettings(
  WebViewController controller,
  CheckoutWebViewSettings settings,
) async {
  final platform = controller.platform;

  if (!settings.paymentRequestEnabled ||
      platform is! AndroidWebViewController) {
    return;
  }

  try {
    if (await platform
        .isWebViewFeatureSupported(WebViewFeatureType.paymentRequest)) {
      await platform.setPaymentRequestEnabled(true);
    }
  } catch (_) {
    return;
  }
}
