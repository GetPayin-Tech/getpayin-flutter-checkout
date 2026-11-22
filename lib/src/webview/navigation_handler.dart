import '../core/navigation.dart';
import '../core/return_url.dart';
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

  /// Whether the page itself asked, rather than a frame inside it.
  ///
  /// `webview_flutter` reports this as `NavigationRequest.isMainFrame`, and reports it on
  /// both platforms: Android from `WebResourceRequest.isForMainFrame`, iOS from
  /// `WKNavigationAction.targetFrame`. The frame rule therefore holds on both, which is not
  /// true of every web view library.
  final bool isTopFrame;
}

/// The decision half of the checkout web view, with no widget and no plugin behind it.
///
/// Each handler completes at most once. The return link can reach a live web view more than
/// once — a redirect followed by the payer's own back navigation, for instance — and a
/// second result for one checkout would be reported as a second payment. One handler
/// belongs to one checkout, so a view that starts a new checkout builds a new handler and
/// one that merely rebuilt keeps the old one.
class CheckoutNavigationHandler {
  /// Creates the handler for one checkout.
  CheckoutNavigationHandler({
    required this.returnUrl,
    required this.onComplete,
    required this.onExternal,
    this.expectedInvoiceId,
    this.ownSchemes = const <String>[],
  });

  /// The link that ends this checkout.
  final String returnUrl;

  /// The invoice this checkout is bound to, if any.
  final Object? expectedInvoiceId;

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
      if (!_completed) {
        _completed = true;
        onComplete(
            resolveReturn(request.url, expectedInvoiceId: expectedInvoiceId));
      }

      return false;
    }

    if (verdict == NavigationVerdict.openExternally) {
      onExternal(request.url);

      return false;
    }

    return verdict == NavigationVerdict.load;
  }
}
