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
}
