import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sessions/registry.dart';

import 'support/fixtures.dart';

Future<CheckoutResult> _presenter(CheckoutRequest request) async {
  return const CheckoutResult(status: CheckoutStatus.paid);
}

Future<CheckoutResult> _otherPresenter(CheckoutRequest request) async {
  return const CheckoutResult(status: CheckoutStatus.cancelled);
}

void main() {
  tearDown(() {
    unregisterPresenter(_presenter);
    unregisterPresenter(_otherPresenter);
  });

  group('the presenter registry', () {
    test('has nothing registered to begin with', () {
      expect(getPresenter(), isNull);
    });

    test('hands back the mounted provider', () async {
      registerPresenter(_presenter);

      final result = await getPresenter()!(testRequest());

      expect(result.status, CheckoutStatus.paid);
    });

    /*
     * A provider mounting over another registers before the old one is disposed, so
     * clearing unconditionally would leave no presenter at all.
     */
    test('keeps the newer provider when an older one unregisters', () {
      registerPresenter(_presenter);
      registerPresenter(_otherPresenter);
      unregisterPresenter(_presenter);

      expect(getPresenter(), _otherPresenter);
    });

    test('clears the registered provider', () {
      registerPresenter(_presenter);
      unregisterPresenter(_presenter);

      expect(getPresenter(), isNull);
    });
  });
}
