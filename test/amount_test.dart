import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

void main() {
  group('formatAmount', () {
    const cases = <(int, String, String)>[
      (9742, 'USD', r'$97.42'),
      (0, 'USD', r'$0.00'),
      (5, 'USD', r'$0.05'),
      (123456789, 'USD', r'$1,234,567.89'),
      (2500, 'EUR', '€25.00'),
      (2500, 'GBP', '£25.00'),
      (25000, 'EGP', 'E£250.00'),
      (2500, 'JPY', '¥2,500'),
      (2500, 'SAR', '25.00 SAR'),
      (25000, 'KWD', '25.000 KWD'),
      (-9742, 'USD', r'-$97.42'),
    ];

    for (final (minor, currency, expected) in cases) {
      test('writes $minor $currency as $expected', () {
        expect(formatAmount(minor, currency), expected);
      });
    }

    test('is not thrown off by a lower-case or padded currency', () {
      expect(formatAmount(9742, ' usd '), r'$97.42');
    });
  });
}
