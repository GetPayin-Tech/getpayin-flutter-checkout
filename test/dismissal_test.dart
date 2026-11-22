import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/sessions/dismissal.dart';

void main() {
  group('SheetDismissalDetector', () {
    test('reports the sheet gone when the app comes back to the front', () {
      final detector = SheetDismissalDetector();

      expect(detector.observe(AppLifecycleState.paused), isFalse);
      expect(detector.observe(AppLifecycleState.resumed), isTrue);
    });

    /*
     * The app is already in front when the sheet is asked for, and the state it reports
     * then must not be read as the sheet having been dismissed before it opened.
     */
    test('says nothing until the app has actually left the front', () {
      expect(
          SheetDismissalDetector().observe(AppLifecycleState.resumed), isFalse);
    });

    test('reads iOS, which only reports the app inactive behind a sheet', () {
      final detector = SheetDismissalDetector();

      expect(detector.observe(AppLifecycleState.inactive), isFalse);
      expect(detector.observe(AppLifecycleState.resumed), isTrue);
    });

    test('reports once per dismissal, not once per resume', () {
      final detector = SheetDismissalDetector();

      detector.observe(AppLifecycleState.paused);

      expect(detector.observe(AppLifecycleState.resumed), isTrue);
      expect(detector.observe(AppLifecycleState.resumed), isFalse);
    });

    test('arms again for a second sheet in the same session', () {
      final detector = SheetDismissalDetector();

      detector.observe(AppLifecycleState.paused);
      detector.observe(AppLifecycleState.resumed);
      detector.observe(AppLifecycleState.hidden);

      expect(detector.observe(AppLifecycleState.resumed), isTrue);
    });
  });
}
