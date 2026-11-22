import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/*
 * The sheet draws Material icons: a back arrow, a close cross, a chevron, a padlock, a card.
 * Their code points live in the private use area, so an app that does not bundle the icon
 * font does not get blank boxes — it gets whichever font the system falls back to, and on
 * Android that is the CJK one. A payer sees Chinese characters where the padlock should be.
 *
 * Nothing in a widget test can see that: the test font draws every glyph the same. The flag
 * that bundles the font is the only thing there is to hold on to.
 */
void main() {
  group('uses-material-design', () {
    const pubspecs = <String, String>{
      'the package': 'pubspec.yaml',
      'the example': 'example/pubspec.yaml',
    };

    pubspecs.forEach((who, path) {
      test('is declared by $who, so the icon font is bundled', () {
        final lines = File(path).readAsLinesSync().map((l) => l.trim());

        expect(
          lines,
          contains('uses-material-design: true'),
          reason: '$path must declare it or every icon renders as a CJK glyph',
        );
      });
    });
  });

  /*
   * Flutter's template puts the INTERNET permission in the debug manifest only, because
   * that is where the tool needs it for hot reload. An app that does not repeat it in the
   * main manifest works all the way through development and then cannot open a socket in
   * release: every call fails with EPERM, the checkout included.
   */
  group('the example manifest', () {
    const manifest = 'example/android/app/src/main/AndroidManifest.xml';

    test('asks for INTERNET, which release builds do not inherit', () {
      expect(
        File(manifest).readAsStringSync(),
        contains('android.permission.INTERNET'),
        reason: 'without it a release build cannot reach GetPayIn at all',
      );
    });
  });
}
