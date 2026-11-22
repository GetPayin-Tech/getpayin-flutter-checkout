import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

void main() {
  final redirect = PaymentReturnRedirect(testReturnUrl);

  group('PaymentReturnRedirect', () {
    test(
        'sends the return link to the first screen instead of an unmatched route',
        () {
      expect(redirect.redirectFor('/payment-return?success=1'), '/');
      expect(redirect.matches('/payment-return?success=1'), isTrue);
    });

    test('matches the marker whatever the separator style', () {
      expect(redirect.matches('payment_return'), isTrue);
      expect(redirect.matches('/Payment-Return'), isTrue);
    });

    test('leaves every other route alone', () {
      expect(redirect.redirectFor('/orders/42'), isNull);
      expect(redirect.matches('/orders/42'), isFalse);
    });

    const similar = <String>[
      '/help/payment-returns-policy',
      '/payment-returns',
      '/orders/payment-return-faq',
    ];

    for (final path in similar) {
      test('leaves $path alone, matching whole segments rather than substrings',
          () {
        expect(redirect.redirectFor(path), isNull);
      });
    }

    test('still matches the return route nested under another segment', () {
      expect(redirect.matches('/app/payment-return?success=1'), isTrue);
    });

    test('honours a custom first screen', () {
      final toHome = PaymentReturnRedirect(testReturnUrl, initialPath: '/home');

      expect(toHome.redirectFor('/payment-return'), '/home');
    });

    test('matches nothing when the return link yields no segments to match on',
        () {
      final empty = PaymentReturnRedirect('');

      expect(empty.matches('/payment-return'), isFalse);
      expect(empty.redirectFor('/'), isNull);
    });

    test('falls back to the raw value when the return link has no scheme', () {
      expect(PaymentReturnRedirect('payment-return').matches('/payment-return'),
          isTrue);
    });
  });
}
