import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';
import 'package:getpayin_flutter_checkout/src/core/validate.dart';

import 'support/fixtures.dart';

void main() {
  group('assertCheckoutUrl', () {
    test('accepts the https URL the server returned', () {
      expect(assertCheckoutUrl(testCheckoutUrl), testCheckoutUrl);
    });

    const refused = <String>[
      'myapp://checkout',
      'not a url',
      '',
      'ftp://pay.getpayin.com'
    ];

    for (final value in refused) {
      test('refuses "$value"', () {
        expect(
          () => assertCheckoutUrl(value),
          throwsA(isA<GetPayInConfigError>()),
        );
      });
    }

    test(
        "hands back the trimmed value it validated, not the caller's raw string",
        () {
      expect(assertCheckoutUrl('  $testCheckoutUrl  '), testCheckoutUrl);
    });
  });

  group('assertReturnUrl', () {
    test('accepts an app scheme', () {
      expect(assertReturnUrl(testReturnUrl), testReturnUrl);
    });

    const refused = <String>['payment-return', '', '://nope'];

    for (final value in refused) {
      test('refuses "$value"', () {
        expect(
            () => assertReturnUrl(value), throwsA(isA<GetPayInConfigError>()));
      });
    }

    test('hands back the trimmed value it validated', () {
      expect(assertReturnUrl(' $testReturnUrl '), testReturnUrl);
    });
  });

  group('assertExpectedInvoiceId', () {
    const accepted = <(String, Object, String)>[
      ('the number the server reported', 4512, '4512'),
      ('the same id as text', '4512', '4512'),
      ('text with stray whitespace', ' 4512 ', '4512'),
      ('leading zeros, which carry no meaning', '004512', '4512'),
      ('an id that is not digits', 'INV-1', 'INV-1'),
    ];

    for (final (label, value, expected) in accepted) {
      test('accepts $label and hands back the text it is compared as', () {
        expect(assertExpectedInvoiceId(value), expected);
      });
    }

    test('accepts no invoice id at all', () {
      expect(assertExpectedInvoiceId(null), isNull);
    });

    const refused = <(String, Object)>[
      ('an empty string', ''),
      ('a blank string', '   '),
      ('NaN', double.nan),
      ('infinity', double.infinity),
      ('a double past the point it holds every digit', 1e21),
      ('a number that is not a whole invoice id', 45.12),
      ('true', true),
      ('the whole init response', <String, Object>{'invoice_id': 4512}),
      ('a list', <int>[4512]),
    ];

    for (final (label, value) in refused) {
      test('refuses $label with GetPayInConfigError', () {
        expect(
          () => assertExpectedInvoiceId(value),
          throwsA(isA<GetPayInConfigError>()),
        );
      });
    }

    test('names a bad value by its type rather than serialising it', () {
      expect(
        () => assertExpectedInvoiceId(<String, Object>{'invoice_id': 1}),
        throwsA(
          isA<GetPayInConfigError>().having(
            (error) => error.message,
            'message',
            contains('a value of type'),
          ),
        ),
      );
    });

    test('shows a bad text value as written', () {
      expect(
        () => assertExpectedInvoiceId('  '),
        throwsA(
          isA<GetPayInConfigError>().having(
            (error) => error.message,
            'message',
            contains('received "  "'),
          ),
        ),
      );
    });
  });
}
