import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../types.dart';
import '../webview/app_schemes.dart';
import '../webview/navigation_handler.dart';
import 'fields_page.dart';
import 'fields_session.dart';
import 'saved_card.dart';

/// The wallet button, rendered by PayLink inside a web view that is never scripted.
///
/// It looks like one more button on the sheet and behaves like one, but it cannot be one: a
/// wallet sheet opens only from a real tap on the wallet's own button, and WebKit turns
/// Apple Pay off on any page the host app has added scripts to. So this surface registers no
/// JavaScript channel and runs no JavaScript — it is told what to do through the fragment of
/// the URL it loads, and it answers the only way an unscripted page can: by navigating to
/// the return link, which is read here exactly as the hosted checkout's is.
class WalletSurface extends StatefulWidget {
  /// Creates the wallet surface.
  const WalletSurface({
    required this.session,
    required this.pageUrl,
    required this.wallet,
    required this.returnUrl,
    required this.onComplete,
    this.expectedInvoiceId,
    this.ownSchemes = const <String>[],
    this.height = 48,
    super.key,
  });

  /// The payment, as `/init` described it.
  final PayLinkFieldsSession session;

  /// The page you host on the origin registered for this integration.
  final String pageUrl;

  /// The one wallet this payment's capture context carries.
  final PaymentWallet wallet;

  /// The link the charge comes back to, which is what ends it.
  final String returnUrl;

  /// The invoice this payment is for, so a link naming another one is refused.
  final Object? expectedInvoiceId;

  /// Other schemes this app answers to, refused like the return link's own.
  final List<String> ownSchemes;

  /// Called once, with the outcome, when the wallet charge comes back.
  final void Function(CheckoutResult result) onComplete;

  /// How tall the button is drawn.
  final double height;

  @override
  State<WalletSurface> createState() => _WalletSurfaceState();
}

class _WalletSurfaceState extends State<WalletSurface> {
  late final CheckoutNavigationHandler _handler = CheckoutNavigationHandler(
    returnUrl: widget.returnUrl,
    expectedInvoiceId: widget.expectedInvoiceId,
    ownSchemes: resolveOwnSchemes(widget.ownSchemes),
    onComplete: (result) => widget.onComplete(result),
    onExternal: (_) {},
  );

  late final WebViewController _webView = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0x00000000))
    ..setNavigationDelegate(
      NavigationDelegate(onNavigationRequest: _onNavigationRequest),
    )
    ..loadRequest(
      Uri.parse(
        walletPageUrl(
          pageUrl: widget.pageUrl,
          clientToken: widget.session.clientToken,
          wallets: <String>[widget.wallet.wireName],
        ),
      ),
    );

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final allowed = _handler(
      NavigationRequestInfo(url: request.url, isTopFrame: request.isMainFrame),
    );

    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: WebViewWidget(controller: _webView),
    );
  }
}
