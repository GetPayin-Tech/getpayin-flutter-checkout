import 'package:shared_preferences/shared_preferences.dart';

/// What the demo remembers between launches.
///
/// A tester on a phone is re-entering the same order, the same tunnel URL and the same
/// integration every time they reinstall or reopen; typing it again is the slowest part of
/// trying anything. So the screen's answers are kept, and the trace of the last attempt
/// with them, because the question "what did it do last time" usually arrives after the app
/// has been closed.
///
/// Deliberately not a settings framework. It reads and writes a flat map of strings and
/// booleans, which is all a one-screen harness has, and it is the only thing in the demo
/// that knows storage exists.
class DemoStore {
  DemoStore._(this._prefs);

  /// Opens the store, or hands back one that remembers nothing if it cannot.
  ///
  /// A demo that will not start because its preferences are unavailable is worse than a
  /// demo that forgets, so a failure here is swallowed and the screen falls back to its
  /// built-in defaults.
  static Future<DemoStore> open() async {
    try {
      return DemoStore._(await SharedPreferences.getInstance());
    } catch (_) {
      return DemoStore._(null);
    }
  }

  final SharedPreferences? _prefs;

  /// What was stored under [key], or [fallback] when nothing was.
  String text(String key, String fallback) {
    final stored = _prefs?.getString(key);

    return stored == null || stored.isEmpty ? fallback : stored;
  }

  /// The switch stored under [key], or [fallback] when it was never set.
  bool flag(String key, {bool fallback = false}) =>
      _prefs?.getBool(key) ?? fallback;

  /// The lines stored under [key], or none.
  List<String> lines(String key) => _prefs?.getStringList(key) ?? <String>[];

  /// Writes a value, and does nothing at all if the store could not be opened.
  Future<void> put(String key, Object? value) async {
    final prefs = _prefs;

    if (prefs == null) {
      return;
    }

    switch (value) {
      case final String text:
        await prefs.setString(key, text);
      case final bool flag:
        await prefs.setBool(key, flag);
      case final List<String> lines:
        await prefs.setStringList(key, lines);
      case null:
        await prefs.remove(key);
      default:
        return;
    }
  }
}
