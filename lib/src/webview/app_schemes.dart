import '../core/url.dart';

/// Reduces a list of declared schemes to the lowercased, deduplicated form the rules use.
///
/// Anything that is not usable text is dropped rather than refused: these come from a
/// declaration the app wrote by hand, and one bad entry must not take the checkout down.
List<String> normalizeSchemes(Iterable<Object?> values) {
  final schemes = <String>{};

  for (final value in values) {
    if (value is! String) {
      continue;
    }

    final scheme = normalizeScheme(value);

    if (scheme.isNotEmpty) {
      schemes.add(scheme);
    }
  }

  return schemes.toList(growable: false);
}

/// The schemes the host app has declared it answers to.
List<String> _declared = const <String>[];

/// Declares every URL scheme this app answers to, so the checkout can refuse them.
///
/// The checkout refuses these whenever a link is not the return link. Refusing only the
/// return link's own scheme is not enough: an app usually answers to several — one per
/// deep-link entry in `AndroidManifest.xml`, one per `CFBundleURLSchemes` entry in
/// `Info.plist`, often its application id as well — and a page inside the checkout could
/// otherwise reach the app's own deep-link routes through one of the others.
///
/// Unlike the Expo package, which reads them out of `app.json`, Flutter has no app config
/// to read at runtime, so the app is what declares them. Call it once at startup, before
/// any checkout:
///
/// ```dart
/// void main() {
///   declareHostAppSchemes(const ['myapp', 'com.shop.app', 'shopdeep']);
///   runApp(const MyApp());
/// }
/// ```
///
/// Declaring nothing leaves the return link's scheme as the only one refused, which is the
/// floor rather than the whole rule.
void declareHostAppSchemes(Iterable<String> schemes) {
  _declared = normalizeSchemes(schemes);
}

/// Every URL scheme the host app has declared, lowercased and deduplicated.
List<String> hostAppSchemes() => _declared;

/// The declared schemes together with the ones passed for a single checkout.
///
/// The per-checkout list is for a screen that knows about a scheme the app-wide declaration
/// does not; neither replaces the other.
List<String> resolveOwnSchemes([Iterable<String>? extra]) {
  if (extra == null || extra.isEmpty) {
    return hostAppSchemes();
  }

  return normalizeSchemes(<String>[...hostAppSchemes(), ...extra]);
}
