/// A URL split into the parts the package compares on.
///
/// Custom app schemes such as `myapp://payment-return` are not what Dart's own [Uri] is
/// shaped for — `Uri.parse('myapp://payment-return')` reads the whole marker as a host,
/// and a backslash or an empty authority is accepted quietly — so this package parses them
/// itself and compares the parts it decided on rather than the ones a general URI parser
/// happens to produce.
class ParsedUrl {
  /// Creates a parsed URL.
  const ParsedUrl({
    required this.scheme,
    required this.authority,
    required this.path,
    required this.query,
  });

  /// The scheme, lowercased: `myapp`, `https`, `mailto`.
  final String scheme;

  /// Everything between `//` and the path, lowercased, or empty when there is none.
  final String authority;

  /// The path, with a leading slash and no trailing one, keeping its case.
  final String path;

  /// The raw query string, undecoded, without the leading `?`.
  final String query;

  @override
  bool operator ==(Object other) {
    return other is ParsedUrl &&
        other.scheme == scheme &&
        other.authority == authority &&
        other.path == path &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(scheme, authority, path, query);

  @override
  String toString() {
    return 'ParsedUrl(scheme: $scheme, authority: $authority, path: $path, query: $query)';
  }
}

/// A scheme followed by an optional authority, which is all this parser recognises.
final RegExp _urlPattern =
    RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):(//)?([\s\S]*)$');

/// Characters that carry no meaning when two names are compared across naming styles.
final RegExp _separators = RegExp(r'[\s_\-.]');

/// One or more trailing slashes.
final RegExp _trailingSlashes = RegExp(r'/+$');

/// Collapses a key or value to a form that compares across naming styles.
String normalizeToken(String value) {
  return value.trim().toLowerCase().replaceAll(_separators, '');
}

/// A scheme's separator as app configurations tend to write it: `myapp://` or `myapp:`.
final RegExp _schemeSeparator = RegExp(r':/*$');

/// Reduces a declared scheme to the form a parsed URL's scheme is compared against.
///
/// `myapp://` and `myapp:` are both written in configuration files, and neither would ever
/// equal the `myapp` a URL parses to. Separators are kept otherwise, unlike
/// [normalizeToken]: `myapp-ios` and `myappios` are two different schemes, and folding them
/// together would refuse a navigation the app never registered.
String normalizeScheme(String scheme) {
  return scheme.trim().toLowerCase().replaceAll(_schemeSeparator, '');
}

/// Strips a trailing slash so `/return` and `/return/` are one target.
String _normalizePath(String path) {
  final withLeadingSlash =
      path.isEmpty || path.startsWith('/') ? path : '/$path';

  return withLeadingSlash.replaceAll(_trailingSlashes, '');
}

/// Splits a URL into scheme, authority, path and query, dropping any fragment.
///
/// Null when the value does not start with a scheme, which is how a relative navigation
/// inside the checkout page is told from a link to somewhere else.
ParsedUrl? parseUrl(String raw) {
  final withoutFragment = raw.trim().split('#').first;
  final queryIndex = withoutFragment.indexOf('?');
  final beforeQuery = queryIndex == -1
      ? withoutFragment
      : withoutFragment.substring(0, queryIndex);
  final query =
      queryIndex == -1 ? '' : withoutFragment.substring(queryIndex + 1);
  final match = _urlPattern.firstMatch(beforeQuery);

  if (match == null) {
    return null;
  }

  final scheme = (match.group(1) ?? '').toLowerCase();
  final hasAuthority = match.group(2) != null;
  final remainder = match.group(3) ?? '';

  if (!hasAuthority) {
    return ParsedUrl(
      scheme: scheme,
      authority: '',
      path: _normalizePath(remainder),
      query: query,
    );
  }

  final pathIndex = remainder.indexOf('/');
  final authority =
      pathIndex == -1 ? remainder : remainder.substring(0, pathIndex);
  final path = pathIndex == -1 ? '' : remainder.substring(pathIndex);

  return ParsedUrl(
    scheme: scheme,
    authority: authority.toLowerCase(),
    path: _normalizePath(path),
    query: query,
  );
}

/// Where [raw] points, for a log line: its scheme and host, and nothing after them.
///
/// A checkout link is signed and can carry the payer's details, and a bank's link its own
/// one-time values, so a log names where a link went and never what it carried.
String linkForLog(String raw) {
  final parsed = parseUrl(raw);

  if (parsed == null) {
    return 'a link with no scheme';
  }

  final host = parsed.authority.split('@').last;

  return host.isEmpty ? '${parsed.scheme}:' : '${parsed.scheme}://$host';
}

/// True when both URLs address the same scheme, host and path, whatever their query.
bool isSameTarget(String a, String b) {
  final left = parseUrl(a);
  final right = parseUrl(b);

  if (left == null || right == null) {
    return false;
  }

  return left.scheme == right.scheme &&
      left.authority == right.authority &&
      left.path == right.path;
}

/// Decodes one query name or value, leaving a malformed escape sequence as it was.
///
/// A malformed sequence is kept rather than thrown on: the link is attacker-controllable,
/// and a throw here would unmount the checkout screen without settling the session.
String decodeQueryComponent(String value) {
  final withSpaces = value.replaceAll('+', ' ');

  try {
    return Uri.decodeComponent(withSpaces);
  } catch (_) {
    return withSpaces;
  }
}

/// Splits a query string into its raw, undecoded name and value pairs, in order.
List<List<String>> _queryPairs(String query) {
  final pairs = <List<String>>[];

  for (final pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }

    final separatorIndex = pair.indexOf('=');

    pairs.add(
      separatorIndex == -1
          ? <String>[pair, '']
          : <String>[
              pair.substring(0, separatorIndex),
              pair.substring(separatorIndex + 1)
            ],
    );
  }

  return pairs;
}

/// Every field name in a query string exactly as sent, in order and undecoded.
///
/// The return-link reader refuses a link carrying a name that only a looser reader would
/// take for one of its own fields — `Success`, `invoiceId`, `%73uccess` — so it has to see
/// the names the way the server checking the link's signature sees them, which is before
/// any decoding or case folding.
List<String> rawQueryNames(String query) {
  return _queryPairs(query).map((pair) => pair.first).toList();
}

/// Reads a query string into every value given for each name, in order.
///
/// Names are decoded but otherwise kept exactly as sent, so `Success` is not `success`. A
/// return link has to be read the way the server that checks its signature reads it: if the
/// two could disagree about which value a field holds, a link could be signed for one
/// invoice and reported for another. Every value is kept so the caller can refuse a name
/// that appears more than once instead of picking one copy.
Map<String, List<String>> readQuery(String query) {
  final params = <String, List<String>>{};

  for (final pair in _queryPairs(query)) {
    final name = decodeQueryComponent(pair[0]);

    params
        .putIfAbsent(name, () => <String>[])
        .add(decodeQueryComponent(pair[1]));
  }

  return params;
}
