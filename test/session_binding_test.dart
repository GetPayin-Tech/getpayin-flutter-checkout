import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('resolveReturn binds a link to the invoice it was opened for', () {
    test('accepts a paid link for the expected invoice', () {
      final result = resolveReturn(
        returnLink('success=1&invoice_id=INV-1'),
        expectedInvoiceId: 'INV-1',
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, 'INV-1');
    });

    test('accepts the invoice id as the number GetPayIn returns from init', () {
      final result = resolveReturn(
        returnLink('success=1&invoice_id=4512'),
        expectedInvoiceId: 4512,
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, '4512');
    });

    test('ignores spaces around the expected invoice id', () {
      expect(
        resolveReturn(returnLink('success=1&invoice_id=4512'),
                expectedInvoiceId: ' 4512 ')
            .status,
        CheckoutStatus.paid,
      );
    });

    const unusable = <(String, Object)>[
      ('an empty string', ''),
      ('a blank string', '  '),
      ('a boolean from untyped code', true),
      ('the whole init response', <String, Object>{'invoice_id': 4512}),
    ];

    for (final (label, expectedInvoiceId) in unusable) {
      test(
          'fails closed on $label: a paid link binds to nothing, so it is refused',
          () {
        final result = resolveReturn(
          returnLink('success=1&invoice_id=4512'),
          expectedInvoiceId: expectedInvoiceId,
        );

        expect(result.status, CheckoutStatus.notPaid);
        expect(result.code, CheckoutResultCode.wrongInvoice);
      });
    }

    test(
        'refuses a genuine link for another invoice with an extra invoiceId in front',
        () {
      // A real signed link for invoice 4000, replayed for a new checkout of invoice 5001.
      final replayed = returnLink(
        'invoiceId=5001&success=1&invoice_id=4000&invoice_status=PAID&signature=c2lnbmF0dXJl',
      );

      final result = resolveReturn(replayed, expectedInvoiceId: 5001);

      // `invoiceId` is a name a looser reader would take for `invoice_id`, so the link is
      // refused as unreadable before the invoice is even compared.
      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.unreadableReturnLink);
    });

    test('refuses a paid link that names a different number', () {
      final result = resolveReturn(
        returnLink('success=1&invoice_id=4513'),
        expectedInvoiceId: 4512,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, contains('different invoice'));
    });

    test('refuses a paid link that names a different invoice', () {
      final result = resolveReturn(
        returnLink('success=1&invoice_id=INV-ATTACKER'),
        expectedInvoiceId: 'INV-1',
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.wrongInvoice);
    });

    test('refuses a paid link that names no invoice at all', () {
      expect(
        resolveReturn(returnLink('success=1'), expectedInvoiceId: 'INV-1')
            .status,
        CheckoutStatus.notPaid,
      );
    });

    test('takes a link at its word when no invoice was supplied to bind to',
        () {
      expect(
        resolveReturn(returnLink('success=1&invoice_id=INV-9')).status,
        CheckoutStatus.paid,
      );
    });

    test(
        'leaves a decline alone rather than rewriting the reason the payer was given',
        () {
      final result = resolveReturn(
        returnLink('success=0&message=Card+declined'),
        expectedInvoiceId: 'INV-1',
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, 'Card declined');
      expect(result.code, isNull);
    });
  });
}
