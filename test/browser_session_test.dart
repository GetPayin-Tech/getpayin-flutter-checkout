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

    test('refuses a return link naming an invoice other than the one opened',
        () async {
      final phone = FakePhone(
        onOpened: (phone) =>
            phone.deliver(returnLink('success=1&invoice_id=INV-ATTACKER')),
      );

      final result = await runBrowserCheckout(
        testRequest(expectedInvoiceId: 'INV-REAL'),
        ports: phone.ports,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.wrongInvoice);
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
