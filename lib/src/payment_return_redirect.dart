import 'core/url.dart';

/// Recognises the payment return link inside a router path, so the router does not try to
/// open it as a screen.
///
/// A deep link reaches the app as a route, and a router that cannot match
/// `/payment-return` shows an error page on top of a checkout that has already been paid.
/// By the time the link arrives this package already has the result — the in-app web view
/// read it off the navigation, and the browser sheet read it off the deep link — so the
/// router's job is only to not get in the way.
///
/// With `go_router`:
///
/// ```dart
/// final paymentReturn = PaymentReturnRedirect('myapp://payment-return');
///
/// GoRouter(
///   redirect: (context, state) => paymentReturn.redirectFor(state.uri.toString()),
///   routes: [...],
/// );
/// ```
///
/// Matching is on whole path segments, so an unrelated route of the app's own that merely
/// reads similarly — `/help/payment-returns-policy`, say — still opens normally.
class PaymentReturnRedirect {
  /// Creates a matcher for the return link [returnUrl] sends the payer to.
  PaymentReturnRedirect(this.returnUrl, {this.initialPath = '/'})
      : _marker = _markerOf(returnUrl);

  /// The return link, exactly as the checkout was opened with it.
  final String returnUrl;

  /// Where to send the payer instead of the unmatched route.
  final String initialPath;

  final List<String> _marker;

  /// True when [path] is the return link arriving as a route.
  bool matches(String path) => _containsSegments(_segmentsOf(path), _marker);

  /// [initialPath] when [path] is the return link, or null to leave the route alone.
  ///
  /// The null is what a router reads as "no redirect", so this drops straight into
  /// `go_router`'s `redirect`.
  String? redirectFor(String path) => matches(path) ? initialPath : null;
}

/// Splits a path into whole, comparable segments, dropping any query or fragment.
List<String> _segmentsOf(String value) {
  final withoutQuery = value.split('#').first.split('?').first;

  return withoutQuery
      .split('/')
      .map(normalizeToken)
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
}

/// The segments the return link is recognised by inside a router path.
List<String> _markerOf(String returnUrl) {
  final parsed = parseUrl(returnUrl);

  if (parsed == null) {
    return _segmentsOf(returnUrl);
  }

  return _segmentsOf('${parsed.authority}/${parsed.path}');
}

/// True when [marker] appears in [segments] as a run of whole segments.
bool _containsSegments(List<String> segments, List<String> marker) {
  if (marker.isEmpty) {
    return false;
  }

  for (var start = 0; start + marker.length <= segments.length; start += 1) {
    var matched = true;

    for (var offset = 0; offset < marker.length; offset += 1) {
      if (segments[start + offset] != marker[offset]) {
        matched = false;
        break;
      }
    }

    if (matched) {
      return true;
    }
  }

  return false;
}
