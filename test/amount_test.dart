import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

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
      (2500, 'SAR', '25.00 SAR'),
      (-9742, 'USD', r'-$97.42'),
      // PayLink keeps every amount in hundredths, whatever the currency: ¥2,500 is
      // 250000 and 25 KWD is 2500. Only the way it is written follows the currency.
      (250000, 'JPY', '¥2,500'),
      (2500, 'JPY', '¥25'),
      (-250000, 'JPY', '-¥2,500'),
      (2500, 'KWD', '25.000 KWD'),
      (9742, 'JOD', '97.420 JOD'),
      (5, 'BHD', '0.050 BHD'),
    ];

    for (final (minor, currency, expected) in cases) {
      test('writes $minor $currency as $expected', () {
        expect(formatAmount(minor, currency), expected);
      });
    }

    test('is not thrown off by a lower-case or padded currency', () {
      expect(formatAmount(9742, ' usd '), r'$97.42');
    });

    test('keeps the hundredths of a no-decimal currency rather than hide them',
        () {
      // Only after a conversion, if ever: what is charged is written as it is, never
      // rounded to a figure the payer will not see on their statement.
      expect(formatAmount(250050, 'JPY'), '¥2,500.50');
    });
  });
}
