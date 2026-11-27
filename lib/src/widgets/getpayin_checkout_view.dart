import 'dart:async';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/intent_link.dart';
import '../core/messages.dart';
import '../core/navigation.dart';
import '../core/return_url.dart';
import '../core/text.dart';
import '../core/url.dart';
import '../platform.dart';
import '../types.dart';
import '../webview/app_schemes.dart';
import '../webview/checkout_source.dart';
import '../webview/external_link.dart';
import '../webview/load_failure.dart';
import '../webview/wallet_settings.dart';
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
    this.onPageLoaded,
    this.onPassedOver,
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

  /// Called each time a page of the checkout finishes loading.
  ///
  /// From the first one the payer can pay, so a failure reported after it is no sign that
  /// nothing was charged: the page that would have said so may be the one that failed. A
  /// screen of your own that is closed then should report the payment as one nobody can
  /// confirm, never as cancelled. A failed page can finish loading too, so read this
  /// against the failure as it arrives rather than when the payer closes.
  final VoidCallback? onPageLoaded;

  /// Called when the page went to a return link that names another invoice, or none.
  ///
  /// Only with [expectedInvoiceId] set. That link is not this checkout's answer, so the view
  /// stops it and goes on; but the real payment may still be running, so a screen of your
  /// own closed after it should report the payment as one nobody can confirm, never as
  /// cancelled.
  final VoidCallback? onPassedOver;

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

  /// The invoice this screen holds a link to, which is the one it was told about or the
  /// one the checkout link itself names.
  Object? get _boundInvoiceId =>
      invoiceBoundTo(widget.expectedInvoiceId, widget.checkoutUrl);

  void _startCheckout() {
    final source = buildCheckoutSource(
      widget.checkoutUrl,
      widget.returnUrl,
      _boundInvoiceId,
    );
    final settings = buildCheckoutWebViewSettings(currentPlatformName());
    final controller = WebViewController();

    /*
     * Every event is tied to the web view that raised it. The one a new checkout replaced
     * goes on running for a moment, and its page can still navigate, finish or fail: through
     * the view's current state, a return link from it would end the new checkout with the
     * old one's answer. Its navigations are stopped, and the rest is dropped.
     */
    bool current() => identical(controller, _controller);

    _loading = true;
    _pageUri = source.uri;
    _handler = CheckoutNavigationHandler(
      returnUrl: source.returnUrl,
      expectedInvoiceId: source.expectedInvoiceId,
      ownSchemes: resolveOwnSchemes(widget.ownSchemes),
      onComplete: (result) => widget.onComplete(result),
      onExternal: _handToPhone,
      onPassedOver: () => widget.onPassedOver?.call(),
    );
    _controller = controller
      ..setJavaScriptMode(
        settings.javaScriptEnabled
            ? JavaScriptMode.unrestricted
            : JavaScriptMode.disabled,
      )
      ..setBackgroundColor(CheckoutStyle.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => current()
              ? _onNavigationRequest(request)
              : NavigationDecision.prevent,
          onPageStarted: (url) {
            if (current()) {
              _pageUri = url;
            }
          },
          onPageFinished: (_) {
            if (current()) {
              _stopLoading();
              widget.onPageLoaded?.call();
            }
          },
          onWebResourceError: (error) {
            if (current()) {
              _onWebResourceError(error);
            }
          },
          onHttpError: (error) {
            if (current()) {
              _onHttpError(error);
            }
          },
        ),
      );

    unawaited(_load(controller, settings, source.uri));

    final error = source.error;

    if (error != null) {
      _reportLoadFailureAfterBuild(controller, error);
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
    await walletSettingsApplier(controller, settings);

    try {
      await controller.loadRequest(Uri.parse(uri));
    } catch (cause) {
      if (identical(controller, _controller)) {
        _reportLoadFailure('$cause');
      }
    }
  }

  FutureOr<NavigationDecision> _onNavigationRequest(NavigationRequest request) {
    final allowed = _handler(
      NavigationRequestInfo(url: request.url, isTopFrame: request.isMainFrame),
    );

    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  void _onWebResourceError(WebResourceError error) {
    if (isMainFrameFailure(error.isForMainFrame) &&
        !isInterruptedLoad(error.errorCode)) {
      _reportLoadFailure('${error.errorType}: ${error.description}');
    }
  }

  void _onHttpError(HttpResponseError error) {
    final status = error.response?.statusCode;

    if (isPageHttpFailure(
      failedUri: error.request?.uri.toString(),
      pageUri: _pageUri,
      beforeFirstPage: _loading,
    )) {
      _reportLoadFailure('The checkout page answered HTTP $status.');
    }
  }

  /// Hands [url] to the phone, or for an `intent:` link, the app it names, then its web page.
  ///
  /// No app answers to `intent:` as written, so it is read the way Chrome reads it, under
  /// the same rules as every other link. What the phone cannot open is shown to the payer.
  void _handToPhone(String url) {
    final intent = readIntentTargets(
      url,
      NavigationContext(
        returnUrl: _handler.returnUrl,
        ownSchemes: _handler.ownSchemes,
        isTopFrame: true,
      ),
    );
    final target = intent == null ? url : intent.app;
    final fallback = intent?.web;
    final controller = _controller;

    /*
     * The phone answers later. By then the app may have swapped in another checkout, or
     * taken this one away, and this bank's page belongs to neither: it is loaded only into
     * the checkout it came from, while that one is still on screen.
     */
    void unopened() {
      if (!mounted || !identical(controller, _controller)) {
        return;
      }

      if (fallback != null) {
        unawaited(
          controller.loadRequest(Uri.parse(fallback)).catchError((Object _) {}),
        );

        return;
      }

      _reportFailure(
        widget.linkErrorMessage,
        defaultLinkErrorMessage,
        detail: 'The phone could not open a link to ${linkForLog(url)}.',
      );
    }

    if (target == null) {
      unopened();

      return;
    }

    unawaited(openExternalLink(target, unopened));
  }

  void _reportLoadFailure([String? detail]) {
    _stopLoading();
    _reportFailure(widget.loadErrorMessage, defaultLoadErrorMessage,
        detail: detail);
  }

  /// Reports a failure found while starting the checkout, once the frame is done.
  ///
  /// The cause is known during `initState`, where telling the parent straight away would
  /// rebuild a widget that is still building. Only for the checkout of [controller]: one
  /// that a new checkout replaced within the frame has nothing left to report.
  void _reportLoadFailureAfterBuild(
      WebViewController controller, String detail) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(controller, _controller)) {
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
