import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/src/webview/checkout_source.dart';

import 'support/fixtures.dart';

void main() {
  group('buildCheckoutSource', () {
    test('hands back what the web view should load', () {
      final source = buildCheckoutSource(testCheckoutUrl, testReturnUrl, 4512);

      expect(source.uri, testCheckoutUrl);
      expect(source.returnUrl, testReturnUrl);
      expect(source.error, isNull);
    });

    test('hands back the invoice id in the form it will be compared as', () {
      expect(
          buildCheckoutSource(testCheckoutUrl, testReturnUrl, 4512)
              .expectedInvoiceId,
          '4512');
      expect(
        buildCheckoutSource(testCheckoutUrl, testReturnUrl, '004512')
            .expectedInvoiceId,
        '4512',
      );
    });

    test('carries no invoice id when none was given', () {
      expect(
        buildCheckoutSource(testCheckoutUrl, testReturnUrl, null)
            .expectedInvoiceId,
        isNull,
      );
    });

    const unusable = <(String, String, String, Object?)>[
      ('an unusable checkout URL', 'myapp://checkout', testReturnUrl, null),
      ('a return link with no scheme', testCheckoutUrl, 'payment-return', null),
      (
        'an invoice id that binds to nothing',
        testCheckoutUrl,
        testReturnUrl,
        ''
      ),
    ];

    for (final (label, checkoutUrl, returnUrl, invoiceId) in unusable) {
      test('reports $label as a value rather than throwing', () {
        final source = buildCheckoutSource(checkoutUrl, returnUrl, invoiceId);

        expect(source.uri, 'about:blank');
        expect(source.error, isNotNull);
      });
    }

    test('names the option and the value in the error, for the log', () {
      final source =
          buildCheckoutSource('myapp://checkout', testReturnUrl, null);

      expect(source.error, contains('checkoutUrl'));
      expect(source.error, contains('myapp://checkout'));
    });
  });
}
