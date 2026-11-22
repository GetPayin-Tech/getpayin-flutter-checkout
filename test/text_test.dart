import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/src/core/text.dart';

void main() {
  group('fallbackText', () {
    test("keeps the caller's text", () {
      expect(fallbackText('Fermer', 'Close'), 'Fermer');
    });

    test('falls back when there is no text at all', () {
      expect(fallbackText(null, 'Close'), 'Close');
    });

    /*
     * A missing translation key yields blank text, and a close button with no label is a
     * payer with no way out of the checkout.
     */
    test('treats blank text as no text', () {
      expect(fallbackText('', 'Close'), 'Close');
      expect(fallbackText('   ', 'Close'), 'Close');
    });
  });
}
