import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';
import 'package:getpayin_flutter_checkout/src/sessions/session_host.dart';

import 'support/fixtures.dart';

void main() {
  group('CheckoutSessionHost', () {
    test('announces the checkout to show and completes with its result',
        () async {
      final shown = <CheckoutRequest?>[];
      final host = CheckoutSessionHost(shown.add);
      final request = testRequest();
      final pending = host.present(request);

      expect(shown.last, request);
      expect(host.current, request);

      host.finish(const CheckoutResult(
          status: CheckoutStatus.paid, invoiceId: 'INV-1'));

      final result = await pending;

      expect(result.invoiceId, 'INV-1');
      expect(shown.last, isNull);
      expect(host.current, isNull);
    });

    test('reports a closed screen as cancelled, with a reason', () async {
      final host = CheckoutSessionHost((_) {});
      final pending = host.present(testRequest());

      host.cancel();

      final result = await pending;

      expect(result.status, CheckoutStatus.cancelled);
      expect(result.message, closedByPayerMessage);
    });

    test('carries a reason of its own when one is given', () async {
      final host = CheckoutSessionHost((_) {});
      final pending = host.present(testRequest());

      host.cancel('the page could not be loaded');

      expect((await pending).message, 'the page could not be loaded');
    });

    test('settles an open checkout when the provider goes away', () async {
      final host = CheckoutSessionHost((_) {});
      final pending = host.present(testRequest());

      host.dispose();

      final result = await pending;

      expect(result.status, CheckoutStatus.cancelled);
      expect(result.message, closedByUnmountMessage);
    });

    test('settles once, so a close after a result does not change it',
        () async {
      final shown = <CheckoutRequest?>[];
      final host = CheckoutSessionHost(shown.add);
      final pending = host.present(testRequest());

      host.finish(const CheckoutResult(status: CheckoutStatus.paid));
      host.cancel();
      host.dispose();

      expect((await pending).status, CheckoutStatus.paid);
      expect(shown, hasLength(2));
    });

    test('ignores a close when nothing is open', () {
      final shown = <CheckoutRequest?>[];
      CheckoutSessionHost(shown.add)
        ..cancel()
        ..dispose()
        ..finish(const CheckoutResult(status: CheckoutStatus.paid));

      expect(shown, isEmpty);
    });

    test('presents a second checkout after the first ended', () async {
      final host = CheckoutSessionHost((_) {});
      final first = host.present(testRequest());

      host.finish(const CheckoutResult(status: CheckoutStatus.paid));
      await first;

      final second = host.present(testRequest());

      host.cancel();

      expect((await second).status, CheckoutStatus.cancelled);
    });
  });
}
