import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

import 'support/fixtures.dart';

/// The link a finished tokenization run comes back on.
///
/// A verification authorizes one unit, vaults the card and releases the hold, so the invoice
/// it ran against ends `VOIDED` — never `PAID`.
String savedLink(
    {String invoiceStatus = 'VOIDED', String invoiceId = '90210'}) {
  return returnLink(
      'success=1&invoice_id=$invoiceId&invoice_status=$invoiceStatus');
}

void main() {
  group('readCardSave', () {
    test('reads a vaulted card off a run whose invoice is deliberately unpaid',
        () {
      final result = readCardSave(savedLink());

      expect(result.status, CardSaveStatus.saved);
      expect(result.isSaved, isTrue);
      expect(result.invoiceId, '90210');
      expect(result.verificationStatus, 'VOIDED');
      expect(result.code, isNull);
    });

    /*
     * The payment reader exists to refuse exactly this, which is why a save needs its own:
     * the same link is a failure as a payment and a success as a card save.
     */
    test('is the opposite verdict to the payment reader on the same link', () {
      final link = savedLink();

      expect(readCardSave(link).status, CardSaveStatus.saved);
      expect(readCheckoutResult(link).status, CheckoutStatus.notPaid);
      expect(readCheckoutResult(link).code,
          CheckoutResultCode.unexpectedInvoiceStatus);
    });

    const states = <String>['AUTHORIZED', 'VOIDED', 'CAPTURED'];

    for (final state in states) {
      test('takes $state as a verification that ran, not as a failure', () {
        expect(readCardSave(savedLink(invoiceStatus: state)).status,
            CardSaveStatus.saved);
      });
    }

    test('reports a card the gateway refused, with the reason and no code', () {
      final result = readCardSave(
        returnLink('success=0&invoice_id=90210&message=Card+declined'),
      );

      expect(result.status, CardSaveStatus.notSaved);
      expect(result.message, 'Card declined');
      expect(result.code, isNull);
    });

    const unreadable = <String>[
      'success=true&invoice_id=90210',
      'invoice_id=90210',
      'success=1&success=0',
      'Success=1&success=1',
      'success=1&invoiceId=5001&invoice_id=90210',
    ];

    for (final query in unreadable) {
      test('refuses "$query", which a payment link reader would refuse too',
          () {
        final result = readCardSave(returnLink(query));

        expect(result.status, CardSaveStatus.notSaved);
        expect(result.code, CheckoutResultCode.unreadableReturnLink);
        expect(result.message, contains('recognises'));
      });
    }

    test('keeps the link it read, for a bug report', () {
      expect(readCardSave(savedLink()).returnUrl, savedLink());
    });
  });

  group('binding a save to the run it was opened for', () {
    test('accepts the verification it was opened for', () {
      expect(
        readCardSave(savedLink(), expectedInvoiceId: 90210).status,
        CardSaveStatus.saved,
      );
    });

    test('refuses a link naming another verification', () {
      final result =
          readCardSave(savedLink(invoiceId: '5001'), expectedInvoiceId: 90210);

      expect(result.status, CardSaveStatus.notSaved);
      expect(result.code, CheckoutResultCode.wrongInvoice);
      expect(result.invoiceId, '5001');
    });

    test('fails closed on an id that cannot name a verification', () {
      expect(
        readCardSave(savedLink(), expectedInvoiceId: '').status,
        CardSaveStatus.notSaved,
      );
    });

    test('takes a link at its word when there is nothing to bind to', () {
      expect(readCardSave(savedLink()).status, CardSaveStatus.saved);
    });

    /// A refused card carries no claim worth checking, so the reason survives the binding.
    test('leaves a refusal alone', () {
      final result = readCardSave(
        returnLink('success=0&invoice_id=5001&message=Card+declined'),
        expectedInvoiceId: 90210,
      );

      expect(result.message, 'Card declined');
      expect(result.code, isNull);
    });
  });

  group('cardSaveFromCheckout', () {
    test('reads the raw link rather than the payment verdict over it', () {
      final checkout = resolveReturn(savedLink(), expectedInvoiceId: 90210);

      expect(checkout.status, CheckoutStatus.notPaid);
      expect(
        cardSaveFromCheckout(checkout, expectedInvoiceId: 90210).status,
        CardSaveStatus.saved,
      );
    });

    test('carries a closed screen through as a cancellation', () {
      final result = cardSaveFromCheckout(cancelledResult('closed'));

      expect(result.status, CardSaveStatus.cancelled);
      expect(result.message, 'closed');
    });

    test('refuses a checkout that came back with no link at all', () {
      final result = cardSaveFromCheckout(
        const CheckoutResult(status: CheckoutStatus.notPaid),
      );

      expect(result.status, CardSaveStatus.notSaved);
      expect(result.code, CheckoutResultCode.unreadableReturnLink);
    });
  });

  group('invoiceIdInCheckoutUrl', () {
    test('reads the verification a tokenization URL names', () {
      expect(
        invoiceIdInCheckoutUrl(
          'https://pay.getpayin.com/integration/checkout?invoice_id=90210&signature=abc',
        ),
        '90210',
      );
    });

    test('is nothing when the URL names none', () {
      expect(invoiceIdInCheckoutUrl(testCheckoutUrl), isNull);
      expect(invoiceIdInCheckoutUrl('not a url'), isNull);
      expect(invoiceIdInCheckoutUrl('https://pay.example.com/x?invoice_id='),
          isNull);
    });
  });

  group('the wire names', () {
    test('describe a save for a log', () {
      expect(CardSaveStatus.saved.wireName, 'saved');
      expect(CardSaveStatus.notSaved.wireName, 'not_saved');
      expect(CardSaveStatus.cancelled.wireName, 'cancelled');
      expect(readCardSave(savedLink()).toString(), contains('saved'));
      expect(readCardSave(savedLink()).toString(), contains('VOIDED'));
    });
  });
}
