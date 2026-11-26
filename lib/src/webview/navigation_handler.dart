import 'package:flutter/foundation.dart'
    show VoidCallback, debugPrint, kDebugMode;

import '../core/navigation.dart';
import '../core/return_url.dart';
import '../core/url.dart';
import '../types.dart';

/// One navigation request, as `webview_flutter` reports it to the navigation delegate.
///
/// [isTopFrame] has no default on purpose. It decides whether a frame inside the checkout
/// page can end the checkout, and a value guessed here would be guessed in favour of the
/// page.
class NavigationRequestInfo {
  /// Creates the request the rule is applied to.
  const NavigationRequestInfo({required this.url, required this.isTopFrame});

  /// Where the page is asking to go.
  final String url;

  /// Whether the main frame is the one being navigated, rather than a frame inside it.
  ///
  /// `webview_flutter` reports this as `NavigationRequest.isMainFrame`, and reports it on
  /// both platforms: Android from `WebResourceRequest.isForMainFrame`, iOS from
  /// `WKNavigationAction.targetFrame`. The frame rule therefore holds on both, which is not
  /// true of every web view library. Both name the frame being navigated rather than the
  /// one that asked for it, which neither platform reports.
  final bool isTopFrame;
}

/// The decision half of the checkout web view, with no widget and no plugin behind it.
///
/// Each handler completes at most once. The return link can reach a live web view more than
/// once — a redirect followed by the payer's own back navigation, for instance — and a
/// second result for one checkout would be reported as a second payment. One handler
/// belongs to one checkout, so a view that starts a new checkout builds a new handler and
/// one that merely rebuilt keeps the old one.
///
/// Bound to an invoice, it passes over a return link that names another invoice, or none:
/// that is not this checkout answering, and a "not paid" in it would end the checkout while
/// the real payment may yet go through. It stops the navigation, tells [onPassedOver], and
/// goes on waiting for its own.
class CheckoutNavigationHandler {
  /// Creates the handler for one checkout.
  CheckoutNavigationHandler({
    required this.returnUrl,
    required this.onComplete,
    required this.onExternal,
    this.expectedInvoiceId,
    this.ownSchemes = const <String>[],
    this.onPassedOver,
  });

  /// The link that ends this checkout.
  final String returnUrl;

  /// The invoice this checkout is bound to, if any.
  final Object? expectedInvoiceId;

  /// Called each time a return link that names another invoice, or none, is passed over.
  ///
  /// The real payment may still be running when it is, so a checkout that then ends with no
  /// answer of its own is one nobody can confirm: report it as
  /// [CheckoutResultCode.outcomeUnknown], never as cancelled.
  final VoidCallback? onPassedOver;

  /// Every other scheme the host app answers to; refused like the return link's scheme.
  final List<String> ownSchemes;

  /// Called once, with the outcome, when the return link arrives.
  final void Function(CheckoutResult result) onComplete;

  /// Called with a link the web view cannot load itself, to hand to the phone.
  final void Function(String url) onExternal;

  bool _completed = false;

  /// Answers the web view's navigation delegate: true to let the navigation happen.
  ///
  /// False stops it, either because something other than the web view is handling it or
  /// because it was refused.
  bool call(NavigationRequestInfo request) {
    final verdict = classifyNavigation(
      request.url,
      NavigationContext(
        returnUrl: returnUrl,
        ownSchemes: ownSchemes,
        isTopFrame: request.isTopFrame,
      ),
    );

    if (verdict == NavigationVerdict.endCheckout) {
      if (!_completed &&
          !returnLinkAnswers(request.url,
              expectedInvoiceId: expectedInvoiceId)) {
        if (kDebugMode) {
          debugPrint(
            'GetPayIn: passed over a return link that names another invoice, or none',
          );
        }

        onPassedOver?.call();
      } else if (!_completed) {
        _completed = true;
        onComplete(
            resolveReturn(request.url, expectedInvoiceId: expectedInvoiceId));
      } else if (kDebugMode) {
        debugPrint(
          'GetPayIn: dropped a second return link; the checkout had already ended',
        );
      }

      return false;
    }

    if (verdict == NavigationVerdict.openExternally) {
      onExternal(request.url);

      return false;
    }

    // In a debug build only, and without what followed the address: a bank's link can carry
    // its own one-time values, and a release build's log is read by whoever reads the phone's.
    if (verdict == NavigationVerdict.block && kDebugMode) {
      debugPrint(
        'GetPayIn: refused a ${request.isTopFrame ? 'page' : 'frame'} link to '
        '${linkForLog(request.url)}',
      );
    }

    return verdict == NavigationVerdict.load;
  }
}
