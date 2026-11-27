import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sessions/browser_session.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  group('runBrowserCheckout', () {
    test('opens the checkout in the sheet', () async {
      final phone = FakePhone(onOpened: (phone) => phone.dismiss());

      await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(phone.opened, <String>[testCheckoutUrl]);
    });

    test(
        'reads the result off a return link that arrives while the sheet is open',
        () async {
      final url = returnLink('success=1&invoice_id=B-1');
      final phone = FakePhone(onOpened: (phone) => phone.deliver(url));

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.paid);
      expect(result.returnUrl, url);
    });

    test('reports a decline the link carried', () async {
      final phone = FakePhone(
        onOpened: (phone) => phone.deliver(
            returnLink('success=0&invoice_id=B-2&message=Card+declined')),
      );

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, 'Card declined');
    });

    /*
     * The sheet can go away before the deep link it was dismissed by reaches the app, and
     * settling on that order would report a completed payment as cancelled.
     */
    test('waits out the grace period for a link the dismissal raced', () async {
      final url = returnLink('success=1&invoice_id=B-3');
      final phone = FakePhone(
        grace: const Duration(milliseconds: 200),
        onOpened: (phone) {
          phone.dismiss();
          Future<void>.delayed(
            const Duration(milliseconds: 20),
            () => phone.deliver(url),
          );
        },
      );

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.paid);
      expect(result.returnUrl, url);
    });

    test('reports a cancellation when no return link follows the dismissal',
        () async {
      final phone = FakePhone(onOpened: (phone) => phone.dismiss());

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.cancelled);
      expect(result.message, closedByPayerMessage);
    });

    test('ignores a link that is not the return link', () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver('https://pay.getpayin.com/checkout/abc?success=1');
          phone.dismiss();
        },
      );

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.cancelled);
    });

    /*
     * A late link from an earlier checkout, or a made-up one, reaches the app the same way
     * as this checkout's own. Bound to an invoice, the sheet takes only a link naming it,
     * and goes on waiting for that one while the payer is still paying.
     */
    test('waits past a return link naming another invoice for its own',
        () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(returnLink('success=1&invoice_id=INV-ATTACKER'));
          phone.deliver(
            returnLink('success=1&invoice_id=INV-REAL&invoice_status=PAID'),
          );
        },
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, 'INV-REAL');
    });

    test('waits past another invoice when only the checkout link names one',
        () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(
            returnLink('success=1&invoice_id=INV-OTHER&invoice_status=PAID'),
          );
          phone.deliver(
            returnLink('success=1&invoice_id=4512&invoice_status=PAID'),
          );
        },
      );

      final result = await runBrowserCheckout(
        testRequest(checkoutUrl: testCheckoutUrlFor(4512)),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.paid);
      expect(
        result.invoiceId,
        '4512',
        reason: 'the checkout link named the invoice, so the link for another '
            'is not this checkout answering',
      );
    });

    /*
     * On Android any link to the app brings it to the front, which reads as the payer
     * closing the sheet. After a link the sheet passed over, the payer may still be paying
     * in the browser behind the app, so the close cannot be reported as cancelled.
     */
    test('waits past a return link naming no invoice', () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(returnLink('success=0&message=Card+declined'));
          phone.dismiss();
        },
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(
        result.status,
        CheckoutStatus.notPaid,
        reason:
            'a decline that names no invoice is not this checkout answering',
      );
      expect(result.code, CheckoutResultCode.outcomeUnknown);
      expect(result.invoiceId, isNull);
    });

    test('is unconfirmed when it closes after a link for another invoice',
        () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(returnLink('success=1&invoice_id=INV-LATE'));
          phone.dismiss();
        },
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
      expect(result.message, closedByPayerMessage);
    });

    /*
     * A server that cannot say how a charge ended answers with a link that names the
     * invoice and carries no `success`. That is this checkout answering, with a result
     * nobody can confirm, so it is taken and read as unreadable rather than passed over.
     */
    test('takes a link it cannot read when it names the invoice', () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(
            returnLink('message=PayLink+did+not+answer&invoice_id=INV-REAL'),
          );
          phone.dismiss();
        },
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.unreadableReturnLink);
    });

    test('waits past a link that names the invoice more than once', () async {
      final phone = FakePhone(
        onOpened: (phone) {
          phone.deliver(
            returnLink('success=1&invoice_id=INV-REAL&invoice_id=INV-OTHER'),
          );
          phone.deliver(
            returnLink('success=1&invoice_id=INV-REAL&invoice_status=PAID'),
          );
        },
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.returnUrl, contains('invoice_status=PAID'));
    });

    test('closes the sheet and stops listening once it is done', () async {
      final phone = FakePhone(
        onOpened: (phone) =>
            phone.deliver(returnLink('success=1&invoice_id=B-4')),
      );

      await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(phone.closes, 1);
      expect(phone.stops, 2);
    });

    test('still returns the result when the sheet cannot be closed', () async {
      final phone = FakePhone(
        onOpened: (phone) =>
            phone.deliver(returnLink('success=1&invoice_id=B-5')),
      )..closeFailure = StateError('no sheet is open');

      final result =
          await runBrowserCheckout(testRequest(), ports: phone.ports);

      expect(result.status, CheckoutStatus.paid);
    });

    test('stops listening and closes the sheet when it cannot be opened at all',
        () async {
      final phone = FakePhone()
        ..openFailure = StateError('no browser available');

      await expectLater(
        runBrowserCheckout(testRequest(), ports: phone.ports),
        throwsStateError,
      );

      expect(phone.stops, 2);
      expect(phone.closes, 1);
    });
  });
}
