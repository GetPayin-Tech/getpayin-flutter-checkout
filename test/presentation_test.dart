import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

void main() {
  group('resolvePresentation', () {
    test('uses the app screen on iOS, where Apple Pay lives', () {
      expect(resolvePresentation(platform: 'ios'), CheckoutPresentation.inApp);
    });

    test('uses the browser sheet on Android before Google approves the app',
        () {
      expect(resolvePresentation(platform: 'android'),
          CheckoutPresentation.browser);
    });

    test('uses the app screen on Android once googlePayInApp is on', () {
      expect(
        resolvePresentation(platform: 'android', googlePayInApp: true),
        CheckoutPresentation.inApp,
      );
    });

    test('falls back to the browser sheet on any other platform', () {
      expect(
          resolvePresentation(platform: 'macos'), CheckoutPresentation.browser);
    });

    test('honours an explicit override', () {
      expect(
        resolvePresentation(
            platform: 'ios', override: CheckoutPresentation.browser),
        CheckoutPresentation.browser,
      );
    });
  });
}
