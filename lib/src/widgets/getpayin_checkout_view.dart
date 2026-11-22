import 'dart:async';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/messages.dart';
import '../core/text.dart';
import '../platform.dart';
import '../types.dart';
import '../webview/app_schemes.dart';
import '../webview/checkout_source.dart';
import '../webview/external_link.dart';
import '../webview/load_failure.dart';
import '../webview/navigation_handler.dart';
import '../webview/platform_settings.dart';
import 'checkout_style.dart';

/// Called when the checkout cannot be shown.
///
/// `message` is the text to show the payer, already in the app's language: whatever
/// `loadErrorMessage` or `linkErrorMessage` was set to, or the English default. `detail`
/// carries the developer-facing cause when there is one — an unusable `checkoutUrl`,
/// `returnUrl` or `expectedInvoiceId` names the option and the value it got. Log `detail`;
/// never show it to a payer.
typedef CheckoutLoadErrorCallback = void Function(
    String message, String? detail);

/// The hosted checkout drawn in the app's own screen.
///
/// `GetPayInProvider` renders this for `GetPayInCheckout.open`. Use it directly to put the
/// checkout in a screen of your own navigation instead of a modal one.
///
/// No JavaScript channel is registered on this web view and `runJavaScript` is never called
/// on it, because WebKit turns Apple Pay off on any page the host app has added scripts to.
///
/// An unusable [checkoutUrl], [returnUrl] or [expectedInvoiceId] is reported through
/// [onLoadError] rather than thrown. They arrive from a server at runtime, and a bad one
/// should not take the screen down with it.
class GetPayInCheckoutView extends StatefulWidget {
  /// Creates a checkout screen for one checkout.
  const GetPayInCheckoutView({
    required this.checkoutUrl,
    required this.returnUrl,
    required this.onComplete,
    this.expectedInvoiceId,
    this.ownSchemes = const <String>[],
    this.loadErrorMessage,
    this.linkErrorMessage,
    this.onLoadError,
    super.key,
  });

  /// The `checkout_url` your server returned. Pass it in memory, never through a route.
  final String checkoutUrl;

  /// The link that ends this checkout, matching the integration's return scheme.
  final String returnUrl;

  /// The invoice this checkout is for, as your server reported it.
  ///
  /// See [CheckoutOptions.expectedInvoiceId] for what is accepted and why it matters.
  final Object? expectedInvoiceId;

  /// Other URL schemes this app answers to, on top of the ones declared app-wide.
  final List<String> ownSchemes;

  /// The text shown to the payer when the checkout page cannot be loaded.
  final String? loadErrorMessage;

  /// The text shown to the payer when the phone cannot open a link the checkout needed.
  final String? linkErrorMessage;

  /// Called once, with the outcome, when the checkout ends.
  final void Function(CheckoutResult result) onComplete;

  /// Called when the checkout cannot be shown.
  final CheckoutLoadErrorCallback? onLoadError;

  @override
  State<GetPayInCheckoutView> createState() => _GetPayInCheckoutViewState();
}

class _GetPayInCheckoutViewState extends State<GetPayInCheckoutView> {
  late WebViewController _controller;

  /// The navigation handler for the checkout being shown.
  ///
  /// It completes at most once, so it is rebuilt when the checkout changes and never
  /// merely because the widget rebuilt: resetting that latch would report one payment
  /// twice. The callbacks reach it through `widget`, which is always the current one.
  late CheckoutNavigationHandler _handler;

  /// The page the payer is on, which is what an HTTP error is judged against.
  String? _pageUri;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startCheckout();
  }

  @override
  void didUpdateWidget(GetPayInCheckoutView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.checkoutUrl != widget.checkoutUrl ||
        oldWidget.returnUrl != widget.returnUrl ||
        oldWidget.expectedInvoiceId != widget.expectedInvoiceId) {
      _startCheckout();
    }
  }

  void _startCheckout() {
    final source = buildCheckoutSource(
      widget.checkoutUrl,
      widget.returnUrl,
      widget.expectedInvoiceId,
    );
    final settings = buildCheckoutWebViewSettings(currentPlatformName());

    _loading = true;
    _pageUri = source.uri;
    _handler = CheckoutNavigationHandler(
      returnUrl: source.returnUrl,
      expectedInvoiceId: source.expectedInvoiceId,
      ownSchemes: resolveOwnSchemes(widget.ownSchemes),
      onComplete: (result) => widget.onComplete(result),
      onExternal: _handToPhone,
    );
    _controller = WebViewController()
      ..setJavaScriptMode(
        settings.javaScriptEnabled
            ? JavaScriptMode.unrestricted
            : JavaScriptMode.disabled,
      )
      ..setBackgroundColor(CheckoutStyle.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (url) => _pageUri = url,
          onPageFinished: (_) => _stopLoading(),
          onWebResourceError: _onWebResourceError,
          onHttpError: _onHttpError,
        ),
      );

    unawaited(_load(_controller, settings, source.uri));

    final error = source.error;

    if (error != null) {
      _reportLoadFailureAfterBuild(error);
    }
  }

  /// Applies the wallet settings, then loads the page.
  ///
  /// In that order, and before the first frame: Android's Payment Request switch — the one
  /// Google Pay needs — takes effect at the next page load, so setting it after the load
  /// would give the payer a checkout with no wallet button and nothing in the log.
  Future<void> _load(
    WebViewController controller,
    CheckoutWebViewSettings settings,
    String uri,
  ) async {
    await _applyWalletSettings(controller, settings);

    try {
      await controller.loadRequest(Uri.parse(uri));
    } catch (cause) {
      _reportLoadFailure('$cause');
    }
  }

  /// Turns on the platform's wallet support, if it has a switch and this build has it.
  ///
  /// A failure is swallowed rather than surfaced: an older WebView that does not know the
  /// feature still takes card payments, and the payer is better served by a checkout with
  /// no Google Pay button than by an error instead of a checkout.
  Future<void> _applyWalletSettings(
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

  FutureOr<NavigationDecision> _onNavigationRequest(NavigationRequest request) {
    final allowed = _handler(
      NavigationRequestInfo(url: request.url, isTopFrame: request.isMainFrame),
    );

    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  void _onWebResourceError(WebResourceError error) {
    if (isMainFrameFailure(error.isForMainFrame)) {
      _reportLoadFailure('${error.errorType}: ${error.description}');
    }
  }

  void _onHttpError(HttpResponseError error) {
    final status = error.response?.statusCode;

    if (isPageHttpFailure(
        failedUri: error.request?.uri.toString(), pageUri: _pageUri)) {
      _reportLoadFailure('The checkout page answered HTTP $status.');
    }
  }

  void _handToPhone(String url) {
    unawaited(
      openExternalLink(url, () {
        _reportFailure(
          widget.linkErrorMessage,
          defaultLinkErrorMessage,
          detail: 'The phone could not open $url.',
        );
      }),
    );
  }

  void _reportLoadFailure([String? detail]) {
    _stopLoading();
    _reportFailure(widget.loadErrorMessage, defaultLoadErrorMessage,
        detail: detail);
  }

  /// Reports a failure found while starting the checkout, once the frame is done.
  ///
  /// The cause is known during `initState`, where telling the parent straight away would
  /// rebuild a widget that is still building.
  void _reportLoadFailureAfterBuild(String detail) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reportLoadFailure(detail);
      }
    });
  }

  void _reportFailure(String? message, String fallback, {String? detail}) {
    widget.onLoadError?.call(fallbackText(message, fallback), detail);
  }

  void _stopLoading() {
    if (_loading && mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CheckoutStyle.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
