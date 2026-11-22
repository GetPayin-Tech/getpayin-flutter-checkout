import 'return_url.dart';
import 'url.dart';

/// What the web view should do with a navigation request.
///
/// Named a verdict rather than a decision because `webview_flutter` has a
/// `NavigationDecision` of its own, with only two values; this one is the rule, and the
/// handler maps it onto the web view's answer.
enum NavigationVerdict {
  /// The return link: end the checkout and read the result off it.
  endCheckout,

  /// A link the web view cannot load itself, handed to the phone.
  openExternally,

  /// Ordinary web content: let the web view load it.
  load,

  /// Refused outright, neither loaded nor handed on.
  block,
}

const Set<String> _webSchemes = <String>{
  'http',
  'https',
  'about',
  'data',
  'blob',
  'file'
};

/// Schemes that are never handed to the phone and never navigated to.
///
/// [NavigationVerdict.openExternally] ends in a launch, and the checkout page is what
/// decides where the web view navigates. A script scheme has no legitimate part in a
/// checkout and must not reach the launcher, where what happens next is up to whatever the
/// phone hands it to.
const Set<String> _blockedSchemes = <String>{'javascript', 'vbscript'};

/// Schemes refused even though another app may well answer to them.
///
/// The page driving a 3-D Secure step is hosted by the issuer, not by GetPayIn, and the
/// link is opened with no confirmation of any kind, so the set of apps a checkout can reach
/// has to exclude the ones with nothing to do with paying: installing something from a
/// store, sending a message on the payer's behalf, running a Shortcuts automation, reading
/// a content provider. None belongs in a card payment, and a browser would refuse most of
/// them from the same page.
///
/// Bank schemes cannot be an allow-list — every acquirer has its own set — so this is the
/// other way round, and `tel:`, `mailto:` and Android's `intent:` stay allowed because a
/// genuine checkout uses them.
const Set<String> _refusedAppSchemes = <String>{
  'market',
  'itms-apps',
  'itms-services',
  'itms-beta',
  'sms',
  'smsto',
  'mms',
  'shortcuts',
  'x-apple-shortcuts',
  'content',
  'android-app',
};

/// What [classifyNavigation] needs in order to decide about one navigation.
class NavigationContext {
  /// Creates the context one navigation is judged in.
  const NavigationContext({
    required this.returnUrl,
    required this.isTopFrame,
    this.ownSchemes = const <String>[],
  });

  /// The link the checkout was opened with, which is what ends it.
  final String returnUrl;

  /// Every other scheme the host app answers to, refused like the return link's scheme.
  ///
  /// `hostAppSchemes()` returns the ones the app declared; pass an empty list only for an
  /// app that answers to nothing but its return link.
  final List<String> ownSchemes;

  /// Whether the navigation was started by the page itself rather than by a frame inside
  /// it. `webview_flutter` reports it as `isMainFrame` on the request, on both platforms.
  ///
  /// A sub-frame gets nothing but ordinary web navigation: an `<iframe>` on the issuer's
  /// 3-D Secure page, which knows the real invoice id, could otherwise point itself at the
  /// return link and end the checkout as paid with no payment made.
  final bool isTopFrame;
}

/// True when [scheme] is one the host app itself answers to.
bool _isOwnScheme(String scheme, NavigationContext context) {
  return scheme == parseUrl(context.returnUrl)?.scheme ||
      context.ownSchemes.any((own) => normalizeScheme(own) == scheme);
}

/// Decides how one navigation request is handled.
///
/// [NavigationVerdict.endCheckout] ends the checkout. [NavigationVerdict.load] stays in the
/// web view. [NavigationVerdict.block] is refused outright. [NavigationVerdict.openExternally]
/// is handed to the phone so a bank app can take a 3-D Secure step and `tel:` or `mailto:`
/// still work. The caller opens it directly (see `openExternalLink`), because asking the
/// phone first answers no for every scheme the host app has not declared.
///
/// The app's own schemes are blocked whenever the link is not the return link: the return
/// link's scheme, and [NavigationContext.ownSchemes], every other scheme the app answers
/// to. A 3-D Secure step is hosted by the issuer, not by GetPayIn, so the page driving these
/// navigations is not one this package controls — and a page that could reach one of the
/// app's schemes would be driving the host app's deep-link routes, which no checkout has any
/// business doing.
///
/// A navigation from a sub-frame can only ever load or be blocked. Nothing a frame inside
/// the page asks for ends the checkout or reaches another app.
NavigationVerdict classifyNavigation(String url, NavigationContext context) {
  final subFrame = !context.isTopFrame;

  if (matchesReturnUrl(url, context.returnUrl)) {
    return subFrame ? NavigationVerdict.block : NavigationVerdict.endCheckout;
  }

  final parsed = parseUrl(url);

  if (parsed == null) {
    return NavigationVerdict.load;
  }

  if (_blockedSchemes.contains(parsed.scheme) ||
      _refusedAppSchemes.contains(parsed.scheme)) {
    return NavigationVerdict.block;
  }

  if (_webSchemes.contains(parsed.scheme)) {
    return NavigationVerdict.load;
  }

  if (_isOwnScheme(parsed.scheme, context)) {
    return NavigationVerdict.block;
  }

  return subFrame ? NavigationVerdict.block : NavigationVerdict.openExternally;
}
