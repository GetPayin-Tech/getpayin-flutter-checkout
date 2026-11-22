import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('matchesReturnUrl', () {
    test('matches the configured link whatever query it carries', () {
      expect(
        matchesReturnUrl(returnLink('success=1&invoice_id=7'), testReturnUrl),
        isTrue,
      );
    });

    test('ignores a trailing slash and the scheme case', () {
      expect(
          matchesReturnUrl('MyApp://payment-return/', testReturnUrl), isTrue);
    });

    test('ignores a fragment', () {
      expect(matchesReturnUrl('myapp://payment-return#done', testReturnUrl),
          isTrue);
    });

    test('rejects another scheme on the same host', () {
      expect(matchesReturnUrl('otherapp://payment-return', testReturnUrl),
          isFalse);
    });

    test('rejects a different path under the same scheme', () {
      expect(matchesReturnUrl('myapp://payment-return/extra', testReturnUrl),
          isFalse);
    });

    test('rejects the checkout page itself', () {
      expect(matchesReturnUrl(testCheckoutUrl, testReturnUrl), isFalse);
    });

    test('rejects an unparseable value', () {
      expect(matchesReturnUrl('not a url', testReturnUrl), isFalse);
    });
  });

  group('readCheckoutResult', () {
    /// The link exactly as GetPayIn's app-return bridge builds it (http_build_query).
    final paidLink = returnLink(
      'success=1&invoice_id=4512&invoice_status=PAID'
      '&message=Payment+completed&signature=c2lnbmF0dXJl&auth_code=831204',
    );

    test("reads GetPayIn's paid return link", () {
      expect(
        readCheckoutResult(paidLink),
        CheckoutResult(
          status: CheckoutStatus.paid,
          invoiceId: '4512',
          invoiceStatus: 'PAID',
          message: 'Payment completed',
          returnUrl: paidLink,
        ),
      );
    });

    test("reads GetPayIn's declined return link", () {
      final result = readCheckoutResult(
        returnLink(
          'success=0&invoice_id=4512&invoice_status=UNPAID'
          '&message=Card+declined&signature=c2lnbmF0dXJl',
        ),
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.invoiceId, '4512');
      expect(result.message, 'Card declined');
      expect(result.code, isNull);
    });

    const invented = <String>[
      'success=true',
      'success=yes',
      'success=2',
      'status=paid',
      'paid=1',
      'result=success',
    ];

    for (final query in invented) {
      test('does not accept $query, which GetPayIn never sends', () {
        final result = readCheckoutResult(returnLink('$query&invoice_id=4512'));

        expect(result.status, CheckoutStatus.notPaid);
        expect(result.message, contains('recognises'));
      });
    }

    const nearMisses = <String>[
      'success=%201%20',
      'success=+1',
      'Success=1',
      'SUCCESS=1',
      'success_=1',
    ];

    for (final query in nearMisses) {
      test(
          'does not accept $query: the flag is read by its exact name and value',
          () {
        expect(readCheckoutResult(returnLink(query)).status,
            CheckoutStatus.notPaid);
      });
    }

    const repeated = <(String, String)>[
      ('success', 'success=1&success=0&invoice_id=4512'),
      ('invoice_id', 'success=1&invoice_id=4512&invoice_id=5001'),
      ('message', 'success=1&invoice_id=4512&message=a&message=b'),
      (
        'a signature, which is what a server disambiguates on',
        'success=1&invoice_id=4512&signature=a&signature=b'
      ),
      (
        'a field GetPayIn adds later',
        'success=1&invoice_id=4512&auth_code=1&auth_code=2'
      ),
    ];

    for (final (field, query) in repeated) {
      test('treats a link that repeats $field as unreadable', () {
        final result = readCheckoutResult(returnLink(query));

        expect(result.status, CheckoutStatus.notPaid);
        expect(result.code, CheckoutResultCode.unreadableReturnLink);
        expect(result.invoiceId, isNull);
      });
    }

    /*
     * A server checking the signature over the raw query string reads these names one way
     * and a reader that folds case, ignores separators or decodes names reads them another.
     * The link is refused rather than read differently by the two.
     */
    const ambiguous = <(String, String)>[
      ('a case variant of the flag', 'Success=0&success=1&invoice_id=7'),
      ('an upper-case variant of the flag', 'SUCCESS=0&success=1&invoice_id=7'),
      ('a percent-encoded field name', '%73uccess=1&invoice_id=7'),
      (
        'an invoice id written in another style',
        'success=1&invoiceId=5001&invoice_id=7'
      ),
      (
        'a separator variant of the status',
        'success=1&invoice-status=PAID&invoice_id=7'
      ),
    ];

    for (final (label, query) in ambiguous) {
      test('refuses $label as unreadable', () {
        final result = readCheckoutResult(returnLink(query));

        expect(result.status, CheckoutStatus.notPaid);
        expect(result.code, CheckoutResultCode.unreadableReturnLink);
      });
    }

    test('is not thrown off by a field named like an object member', () {
      expect(
        readCheckoutResult(returnLink(
                'hashCode=x&runtimeType=y&success=1&invoice_id=4512'))
            .status,
        CheckoutStatus.paid,
      );
    });

    test('leaves a malformed escape sequence alone rather than throwing', () {
      final result =
          readCheckoutResult(returnLink('success=0&message=100%25%ZZ'));

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, contains('%ZZ'));
    });

    test('reports a link without the success flag as not paid, never as paid',
        () {
      final result = readCheckoutResult(returnLink('invoice_id=4512'));

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, contains('recognises'));
    });

    test('reports a blank success flag as unreadable', () {
      expect(
        readCheckoutResult(returnLink('success=&invoice_id=4512')).code,
        CheckoutResultCode.unreadableReturnLink,
      );
    });

    test('carries no invoice or message when the link carries neither', () {
      final result = readCheckoutResult(returnLink('success=1'));

      expect(result.invoiceId, isNull);
      expect(result.message, isNull);
    });

    test('reports an unparseable return link as not paid', () {
      final result = readCheckoutResult('nonsense');

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.returnUrl, 'nonsense');
    });

    /*
     * GetPayIn's bridge always sends a message, so without a code of its own an unreadable
     * link would arrive looking exactly like a genuine decline — and nothing would be left
     * to alert on when the backend and this reader stop agreeing about the link's shape.
     */
    test(
        'marks an unreadable link with a code a genuine decline does not carry',
        () {
      final unreadable = readCheckoutResult(
          returnLink('invoice_id=4512&message=Payment+declined'));
      final declined = readCheckoutResult(
          returnLink('success=0&invoice_id=4512&message=Payment+declined'));

      expect(unreadable.code, CheckoutResultCode.unreadableReturnLink);
      expect(declined.code, isNull);
    });

    test(
        "does not show the payer the link's own message when it could not be read",
        () {
      final result = readCheckoutResult(
        returnLink('success=true&invoice_id=4512&message=Payment+completed'),
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, contains('recognises'));
      expect(result.invoiceId, isNull);
    });

    test('treats a blank message as no message at all', () {
      expect(readCheckoutResult(returnLink('success=0&message=+')).message,
          isNull);
    });

    test('reads the invoice status the link reported', () {
      expect(
        readCheckoutResult(
                returnLink('success=1&invoice_id=4512&invoice_status=PAID'))
            .invoiceStatus,
        'PAID',
      );
    });

    const notSettled = <String>[
      'PARTIALLY_PAID',
      'AUTHORIZED',
      'UNPAID',
      'REFUNDED'
    ];

    for (final invoiceStatus in notSettled) {
      test('refuses a paid flag carrying invoice_status=$invoiceStatus', () {
        final result = readCheckoutResult(
          returnLink('success=1&invoice_id=4512&invoice_status=$invoiceStatus'),
        );

        expect(result.status, CheckoutStatus.notPaid);
        expect(result.code, CheckoutResultCode.unexpectedInvoiceStatus);
        expect(result.invoiceStatus, invoiceStatus);
      });
    }

    test('does not let invoice_status upgrade a declined link to paid', () {
      final result = readCheckoutResult(
          returnLink('success=0&invoice_id=4512&invoice_status=PAID'));

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, isNull);
    });

    test('still reads a paid link that carries no invoice status at all', () {
      expect(
        readCheckoutResult(returnLink('success=1&invoice_id=4512')).status,
        CheckoutStatus.paid,
      );
    });
  });

  group('cancelledResult', () {
    test('reports a cancellation with no invoice', () {
      expect(cancelledResult(),
          const CheckoutResult(status: CheckoutStatus.cancelled));
    });

    test('carries a reason when one is given', () {
      expect(
        cancelledResult('closed'),
        const CheckoutResult(
            status: CheckoutStatus.cancelled, message: 'closed'),
      );
    });
  });
}
