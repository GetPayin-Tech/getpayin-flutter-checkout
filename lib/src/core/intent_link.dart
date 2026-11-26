import 'navigation.dart';
import 'url.dart';

/// Where an Android `intent:` link can go, under the rules every other link is held to.
class IntentTargets {
  /// Creates the targets one `intent:` link was read as.
  const IntentTargets({this.app, this.web});

  /// The link in the app's own scheme, to hand to the phone, or null when the link names
  /// none, or names one a checkout may not open.
  final String? app;

  /// The web page to load in the checkout when no app takes [app], or null when the link
  /// names none, or names something that is not a web page.
  final String? web;
}

/// The part of an `intent:` link that carries its details.
const String _detailsMarker = '#Intent;';

/// Schemes a fallback may use: it is loaded in the checkout, so it has to be a web page.
const Set<String> _webSchemes = <String>{'https', 'http'};

/// Reads an Android `intent:` link the way Chrome does, or null for any other link.
///
/// A bank's 3-D Secure step can send one, and no app answers to `intent:` as written: the
/// link names the app it is for, by its `scheme`, and the web page for when no app takes it,
/// by `S.browser_fallback_url`. Both are held to [context]'s rules, so an `intent:` link
/// reaches nothing a plain link could not: no refused app, none of the host app's own
/// schemes, and as a fallback only an ordinary web page.
IntentTargets? readIntentTargets(String url, NavigationContext context) {
  final link = url.trim();

  if (!link.toLowerCase().startsWith('intent:')) {
    return null;
  }

  final marker = link.indexOf(_detailsMarker);
  final body = marker == -1 ? link : link.substring(0, marker);
  final details = _detailsOf(
    marker == -1 ? '' : link.substring(marker + _detailsMarker.length),
  );
  final scheme = details['scheme'];
  final app = scheme == null || scheme.isEmpty
      ? null
      : '$scheme:${body.substring('intent:'.length)}';

  return IntentTargets(
    app: app != null && _opens(app, context) ? app : null,
    web: _webPage(details['S.browser_fallback_url'], context),
  );
}

/// The `key=value` pairs between `#Intent;` and `end`.
Map<String, String> _detailsOf(String details) {
  final found = <String, String>{};

  for (final part in details.split(';')) {
    final equals = part.indexOf('=');

    if (equals > 0) {
      found[part.substring(0, equals)] = part.substring(equals + 1);
    }
  }

  return found;
}

/// Whether [link] is one the checkout hands to the phone, and not itself an `intent:` link.
bool _opens(String link, NavigationContext context) =>
    parseUrl(link)?.scheme != 'intent' &&
    classifyNavigation(link, context) == NavigationVerdict.openExternally;

/// The fallback, decoded, when it is a web page the checkout may load.
///
/// It has to be one the web view can be handed, too: a link that passes the rules but
/// that `Uri` cannot read, such as a host with an unclosed `[`, would throw in the middle
/// of the checkout's navigation instead of telling the payer anything. So would decoding
/// one: a cut-off escape throws an `ArgumentError`, and an escape that is not UTF-8 a
/// `FormatException`, so any throw means there is no page.
String? _webPage(String? encoded, NavigationContext context) {
  if (encoded == null) {
    return null;
  }

  final String page;

  try {
    page = Uri.decodeComponent(encoded);
  } catch (_) {
    return null;
  }

  final isWebPage = _webSchemes.contains(parseUrl(page)?.scheme) &&
      Uri.tryParse(page) != null &&
      classifyNavigation(page, context) == NavigationVerdict.load;

  return isWebPage ? page : null;
}
