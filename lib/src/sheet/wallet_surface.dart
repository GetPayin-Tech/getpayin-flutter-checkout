import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../platform.dart';
import '../types.dart';
import '../webview/app_schemes.dart';
import '../webview/navigation_handler.dart';
import '../webview/platform_settings.dart';
import '../webview/wallet_settings.dart';
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
    this.onCharging,
    this.onChargingAfterLeaving,
    this.pageHeaders = const <String, String>{},
    this.expectedInvoiceId,
    this.ownSchemes = const <String>[],
    this.height = 48,
    super.key,
  });

  /// The payment, as `/init` described it.
  final PayLinkFieldsSession session;

  /// The page you host on the origin registered for this integration.
  final String pageUrl;

  /// Headers the page is asked for with, for an origin that will not serve it without.
  final Map<String, String> pageHeaders;

  /// The one wallet this payment's capture context carries.
  final PaymentWallet wallet;

  /// The link the charge comes back to, which is what ends it.
  final String returnUrl;

  /// The invoice this payment is for, so a link naming another one is refused.
  final Object? expectedInvoiceId;

  /// Other schemes this app answers to, refused like the return link's own.
  final List<String> ownSchemes;

  /// Called once, with the outcome, when the wallet charge comes back.
  ///
  /// Only while the surface is on screen: keep it in the tree until this is called. A
  /// surface that leaves ends its page and never calls this; a charge its page had already
  /// marked goes to [onChargingAfterLeaving].
  final void Function(CheckoutResult result) onComplete;

  /// Called once, when the page says the wallet's charge is out and its answer is due.
  ///
  /// The charge runs for a few seconds after the wallet's own sheet has closed, and a host
  /// that closes in that window reports a payment that may well go through as one that did
  /// not. Hold the surface still until [onComplete].
  ///
  /// Only while the surface is on screen. A mark that arrives after it has left goes to
  /// [onChargingAfterLeaving] instead, so this one always belongs to the button showing.
  final VoidCallback? onCharging;

  /// Called once, when the page marked its charge just before the surface left the screen.
  ///
  /// That charge is out, and [onComplete] will not follow: its answer arrives on a page
  /// that is gone. Report the payment as unconfirmed rather than trust any other answer,
  /// including one from a new surface in this one's place. It can run after your own widget
  /// has gone, so check `mounted` before calling `setState`.
  final VoidCallback? onChargingAfterLeaving;

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
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onUrlChange: (change) => _noticeCharging(change.url),
      ),
    );

  /// True once the host has been told the wallet's charge is out.
  bool _chargingNoticed = false;

  /// True once the surface has left the screen, after which it passes on only the page's
  /// mark that its charge is out.
  bool _stopped = false;

  /// The host's [WalletSurface.onChargingAfterLeaving], as it was when the surface left the
  /// screen.
  VoidCallback? _onChargingAfterLeaving;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Empties the page as the surface leaves the screen.
  ///
  /// The web view outlives the widget, and the page in it goes on with whatever it was
  /// doing: a wallet charge it was still preparing goes out seconds later. Seen on an
  /// Android emulator, where an invoice was paid after the sheet holding its button had
  /// closed. A host that takes the surface away has stopped waiting on it, so a charge from
  /// it then is one nobody is holding still for — beside, it may be, the next thing the
  /// payer pays with. Loading a blank page ends the old one. A charge it had already sent
  /// goes on regardless: its mark, if the page made one, goes to
  /// [WalletSurface.onChargingAfterLeaving], so the host can report the payment
  /// unconfirmed, and nothing else is passed on.
  @override
  void dispose() {
    _stopped = true;
    _onChargingAfterLeaving = widget.onChargingAfterLeaving;
    unawaited(
      _webView.loadRequest(Uri.parse('about:blank')).catchError((Object _) {}),
    );
    super.dispose();
  }

  /// Turns the platform's wallet support on, then loads the page.
  ///
  /// In that order, and nowhere else: Android reads its Payment Request switch at the next
  /// page load, so a surface that loads first renders a button-shaped nothing. The whole
  /// point of this surface is the button, which makes this the one call it cannot skip.
  ///
  /// A surface that left the screen while the switch was being set loads nothing: Android
  /// never asks the navigation delegate about a page the app loads itself, so the page would
  /// otherwise come up behind the blank one, holding the payment's token.
  Future<void> _load() async {
    await walletSettingsApplier(
      _webView,
      buildCheckoutWebViewSettings(currentPlatformName()),
    );

    if (_stopped) {
      return;
    }

    await _webView.loadRequest(
      Uri.parse(
        walletPageUrl(
          pageUrl: widget.pageUrl,
          clientToken: widget.session.clientToken,
          wallets: <String>[widget.wallet.wireName],
          sdkUrl: widget.session.sdkUrl,
        ),
      ),
      headers: widget.pageHeaders,
    );
  }

  /// Passes the page's mark that its charge is out on to the host, once.
  ///
  /// Read off both callbacks because the platforms report a fragment the page sets on itself
  /// differently: iOS asks the navigation delegate, Android only reports the new address.
  /// Passed on after the surface has left the screen too, to the host's other callback: the
  /// page may have marked its charge just before it was emptied, and that charge is out.
  void _noticeCharging(String? url) {
    final fragment = url == null ? null : Uri.tryParse(url)?.fragment;

    if (_chargingNoticed || fragment != walletChargingFragment) {
      return;
    }

    _chargingNoticed = true;
    (_stopped ? _onChargingAfterLeaving : widget.onCharging)?.call();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    if (_stopped) {
      if (request.isMainFrame) {
        _noticeCharging(request.url);
      }

      return request.url == 'about:blank'
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }

    if (request.isMainFrame) {
      _noticeCharging(request.url);
    }

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
