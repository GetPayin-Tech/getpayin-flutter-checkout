import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/return_url.dart';
import '../core/url.dart';
import '../platform.dart';
import '../types.dart';
import '../webview/app_schemes.dart';
import '../webview/load_failure.dart';
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
    this.onUnavailable,
    this.onChallenge,
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

  /// Called once, when the page says it cannot show the wallet.
  ///
  /// The page did not load or has gone, was sent to another website before it loaded,
  /// refused the SDK address it was sent, could not start, or the wallet is not available
  /// on this phone. Never called after the page marked
  /// its charge, so nothing was charged through it. Take the surface away: left in place, it
  /// is an empty row where a wallet should be.
  final VoidCallback? onUnavailable;

  /// Called with true when the page shows the issuer's 3-D Secure check, and with false when
  /// the check has gone with no charge.
  ///
  /// PayLink's SDK draws the check over the whole page, so give the surface the room the
  /// card's check gets, by [height], until this says false or [onCharging] is called: a
  /// check that is passed is followed by the charge. Keep the same surface on screen
  /// meanwhile, because a new one loads a new page and the check is lost. The payer is part
  /// way through a payment while it is up, so hold the host still as for a charge. Only
  /// while the surface is on screen and before its charge is marked.
  final ValueChanged<bool>? onChallenge;

  /// How tall the button is drawn.
  final double height;

  @override
  State<WalletSurface> createState() => _WalletSurfaceState();
}

/// Schemes a web view loads as a page that has no web address of its own.
const Set<String> _pagesWithNoAddress = <String>{
  'about',
  'data',
  'blob',
  'file'
};

class _WalletSurfaceState extends State<WalletSurface> {
  late final CheckoutNavigationHandler _handler = CheckoutNavigationHandler(
    returnUrl: widget.returnUrl,
    expectedInvoiceId: widget.expectedInvoiceId,
    ownSchemes: resolveOwnSchemes(widget.ownSchemes),
    onComplete: (result) => widget.onComplete(result),
    onExternal: (url) {
      if (kDebugMode) {
        debugPrint('GetPayIn wallet: refused a link to ${linkForLog(url)}');
      }
    },
  );

  late final WebViewController _webView = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0x00000000))
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onUrlChange: (change) => _noticeCharging(change.url),
        onWebResourceError: (error) {
          if (isMainFrameFailure(error.isForMainFrame) &&
              !isInterruptedLoad(error.errorCode)) {
            _unavailable();
          }
        },
        onPageFinished: (_) => _pageUp = true,
        onHttpError: (error) {
          if (isPageHttpFailure(
            failedUri: error.request?.uri.toString(),
            pageUri: widget.pageUrl,
            beforeFirstPage: !_pageUp,
          )) {
            _unavailable();
          }
        },
      ),
    );

  /// Tells the host the wallet cannot be shown, once, while nothing has been charged.
  ///
  /// The page says so on its address when it cannot start the wallet. A page that never
  /// loaded cannot say anything, so a load that fails says it for the page.
  void _unavailable() {
    if (_stopped || _chargingNoticed || _unavailableNoticed) {
      return;
    }

    _unavailableNoticed = true;
    widget.onUnavailable?.call();
  }

  /// True once the host has been told the wallet's charge is out.
  bool _chargingNoticed = false;

  /// True once the host has been told the page cannot show the wallet.
  bool _unavailableNoticed = false;

  /// True while the host has been told the issuer's check is up.
  bool _challengeNoticed = false;

  /// True once the wallet's page has finished loading for the first time.
  bool _pageUp = false;

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
  ///
  /// A surface that cannot be set up or loaded tells the host it is unavailable, rather
  /// than leaving an empty row behind.
  Future<void> _load() async {
    try {
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
    } catch (cause) {
      // The kind of failure only: its text can carry the page's address, and the address
      // carries the payment's client token.
      if (kDebugMode) {
        debugPrint(
            'GetPayIn wallet: could not load its page (${cause.runtimeType})');
      }

      _unavailable();
    }
  }

  /// Passes the page's mark that its charge is out on to the host, once.
  ///
  /// Read off both callbacks because the platforms report a fragment the page sets on itself
  /// differently: iOS asks the navigation delegate, Android only reports the new address.
  /// Passed on after the surface has left the screen too, to the host's other callback: the
  /// page may have marked its charge just before it was emptied, and that charge is out.
  ///
  /// The page's marks that it cannot show the wallet, and that the issuer's check is up or
  /// has gone, are read the same way, and passed on only while the surface is on screen and
  /// no charge has been marked.
  void _noticeCharging(String? url) {
    final fragment = url == null ? null : Uri.tryParse(url)?.fragment;

    if (fragment == walletUnavailableFragment) {
      _unavailable();

      return;
    }

    if (fragment == walletChallengeFragment ||
        fragment == walletChallengeEndedFragment) {
      _challenge(showing: fragment == walletChallengeFragment);

      return;
    }

    if (_chargingNoticed || fragment != walletChargingFragment) {
      return;
    }

    _chargingNoticed = true;
    _challengeNoticed = false;
    (_stopped ? _onChargingAfterLeaving : widget.onCharging)?.call();
  }

  /// Tells the host the issuer's check is up, or has gone with no charge, once per change.
  ///
  /// Both platforms can report the same mark twice: iOS as a navigation, Android as a new
  /// address.
  void _challenge({required bool showing}) {
    if (_stopped || _chargingNoticed || _challengeNoticed == showing) {
      return;
    }

    _challengeNoticed = showing;
    widget.onChallenge?.call(showing);
  }

  /// Whether [url] may hold the top of the wallet's page: a web page only if it is the
  /// shop's own or PayLink's.
  ///
  /// This page is the one the sheet takes the wallet's return link from, so a page it is
  /// sent to could hand back a "paid" for this invoice. The shop's page is the wallet's own,
  /// on the origin the integration registered. PayLink's is where a "Mobile App"
  /// integration's return link goes first, a page that forwards the payer to the app's
  /// link; any other integration's return link is the shop's own address. Anything that is
  /// not a web page — the return link, a bank's app — is the navigation handler's to judge,
  /// and so is a web return link. A page with no address of its own (`about:`, `data:`,
  /// `blob:`, `file:`) is none of the three, so it is refused, as the card box refuses it;
  /// the blank page that ends a surface that left is let through before this is asked.
  /// Frames are never judged here: the wallet and the bank draw their own steps in them.
  bool _mayHoldTopFrame(String url) {
    final scheme = parseUrl(url)?.scheme;

    if (_pagesWithNoAddress.contains(scheme)) {
      return false;
    }

    if ((scheme != 'http' && scheme != 'https') ||
        matchesReturnUrl(url, widget.returnUrl)) {
      return true;
    }

    return widget.session.servesFrom(url) || _isPayLinks(url);
  }

  /// Whether [url] is served from the PayLink the payment's checkout is on.
  bool _isPayLinks(String url) {
    final page = parseUrl(url);
    final payLink = parseUrl(widget.session.checkoutUrl);

    return page != null &&
        payLink != null &&
        page.scheme == payLink.scheme &&
        page.authority == payLink.authority;
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

      if (!_mayHoldTopFrame(request.url)) {
        if (kDebugMode) {
          debugPrint(
            'GetPayIn wallet: refused to let its page go to ${linkForLog(request.url)}',
          );
        }

        if (!_pageUp) {
          _unavailable();
        }

        return NavigationDecision.prevent;
      }
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
