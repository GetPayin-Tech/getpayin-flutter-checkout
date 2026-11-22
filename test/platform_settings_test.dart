import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

void main() {
  group('buildCheckoutWebViewSettings', () {
    test('turns on Apple Pay and no script injection on iOS', () {
      const settings = CheckoutWebViewSettings(
          javaScriptEnabled: true, applePayEnabled: true);

      expect(buildCheckoutWebViewSettings('ios'), settings);
      expect(
          buildCheckoutWebViewSettings('ios').paymentRequestEnabled, isFalse);
    });

    test('turns on the Payment Request API that Google Pay needs on Android',
        () {
      final settings = buildCheckoutWebViewSettings('android');

      expect(settings.paymentRequestEnabled, isTrue);
      expect(settings.applePayEnabled, isFalse);
    });

    test('still runs JavaScript anywhere else: the checkout page needs it', () {
      expect(buildCheckoutWebViewSettings('macos').javaScriptEnabled, isTrue);
    });

    test('never turns JavaScript off, on any platform', () {
      for (final platform in <String>['ios', 'android', 'macos']) {
        expect(
            buildCheckoutWebViewSettings(platform).javaScriptEnabled, isTrue);
      }
    });
  });
}
