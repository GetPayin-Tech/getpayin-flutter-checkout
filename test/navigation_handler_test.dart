import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

/// A handler with its two callbacks recorded, and the two ways a page can navigate.
class _Harness {
  _Harness(
      {Object? expectedInvoiceId, List<String> ownSchemes = const <String>[]}) {
    handler = CheckoutNavigationHandler(
      returnUrl: testReturnUrl,
      expectedInvoiceId: expectedInvoiceId,
      ownSchemes: ownSchemes,
      onComplete: results.add,
      onExternal: external.add,
      onPassedOver: () => passedOver += 1,
    );
  }

  late final CheckoutNavigationHandler handler;
  final List<CheckoutResult> results = <CheckoutResult>[];
  final List<String> external = <String>[];
  int passedOver = 0;

  bool navigate(String url) =>
      handler(NavigationRequestInfo(url: url, isTopFrame: true));

  bool navigateInFrame(String url) =>
      handler(NavigationRequestInfo(url: url, isTopFrame: false));
}

void main() {
  group('CheckoutNavigationHandler', () {
    test('lets the checkout itself load', () {
      final harness = _Harness();

      expect(harness.navigate(testCheckoutUrl), isTrue);
      expect(harness.results, isEmpty);
      expect(harness.external, isEmpty);
    });

    test('completes on the return link and stops the navigation', () {
      final harness = _Harness();

      expect(
          harness.navigate(returnLink('success=1&invoice_id=INV-3')), isFalse);
      expect(harness.results, hasLength(1));
      expect(harness.results.single.status, CheckoutStatus.paid);
      expect(harness.results.single.invoiceId, 'INV-3');
    });

    test('completes at most once, however often the return link arrives', () {
      final harness = _Harness();

      expect(harness.navigate(returnLink('success=1')), isFalse);
      expect(harness.navigate(returnLink('success=0')), isFalse);
      expect(harness.navigate(returnLink('success=1')), isFalse);

      expect(harness.results, hasLength(1));
      expect(harness.results.single.status, CheckoutStatus.paid);
    });

    /*
     * A link naming another invoice is not this checkout answering, paid or not: a late link
     * from an earlier checkout, or a made-up one. Taken, a "not paid" in it would end the
     * checkout the payer is still in while the real payment may yet go through.
     */
    for (final claim in <String>['success=1', 'success=0']) {
      test('passes over a $claim link that names another invoice', () {
        final harness = _Harness(expectedInvoiceId: 'INV-1');

        expect(
          harness.navigate(returnLink('$claim&invoice_id=INV-ATTACKER')),
          isFalse,
        );
        expect(harness.results, isEmpty);
        expect(harness.passedOver, 1);

        harness.navigate(returnLink('success=1&invoice_id=INV-1'));

        expect(harness.results.single.status, CheckoutStatus.paid);
        expect(harness.results.single.invoiceId, 'INV-1');
      });
    }

    test('passes over a link that names no invoice when bound to one', () {
      final harness = _Harness(expectedInvoiceId: 'INV-1');

      expect(harness.navigate(returnLink('success=0')), isFalse);
      expect(harness.results, isEmpty);
      expect(harness.passedOver, 1);
    });

    test('takes a link naming its invoice even when its result cannot be read',
        () {
      final harness = _Harness(expectedInvoiceId: 'INV-1');

      harness.navigate(returnLink('success=maybe&invoice_id=INV-1'));

      expect(
          harness.results.single.code, CheckoutResultCode.unreadableReturnLink);
      expect(harness.passedOver, 0);
    });

    test('hands a bank app to the phone and stops the navigation', () {
      final harness = _Harness();

      expect(harness.navigate('mybank://authorise/3ds/1'), isFalse);
      expect(harness.external, <String>['mybank://authorise/3ds/1']);
    });

    test('refuses a script scheme without handing it anywhere', () {
      final harness = _Harness();

      expect(harness.navigate('javascript:alert(1)'), isFalse);
      expect(harness.external, isEmpty);
      expect(harness.results, isEmpty);
    });

    test('says in a debug log what it refused, without what the link carried',
        () {
      final printed = <String>[];
      final original = debugPrint;

      debugPrint =
          (String? message, {int? wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = original);

      _Harness().navigate('market://details?id=com.bank&token=secret');

      expect(printed, contains(contains('market://details')));
      expect(printed.join(), isNot(contains('secret')));
    });

    test('says in a debug log that it dropped a second return link', () {
      final printed = <String>[];
      final original = debugPrint;

      debugPrint =
          (String? message, {int? wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = original);

      final harness = _Harness();

      harness.navigate(returnLink('success=1'));
      harness.navigate(returnLink('success=0'));

      expect(printed, contains(contains('second return link')));
    });

    test("refuses another of the app's own schemes", () {
      final harness = _Harness(ownSchemes: <String>['com.shop.app']);

      expect(harness.navigate('com.shop.app://orders/1'), isFalse);
      expect(harness.external, isEmpty);
    });

    test('never completes or reaches the phone for a frame inside the page',
        () {
      final harness = _Harness();

      expect(harness.navigateInFrame(returnLink('success=1&invoice_id=4512')),
          isFalse);
      expect(harness.navigateInFrame('mybank://authorise/3ds/9'), isFalse);
      expect(harness.results, isEmpty);
      expect(harness.external, isEmpty);
    });

    test('still loads ordinary web content inside a frame', () {
      expect(_Harness().navigateInFrame('https://3ds.issuer.example/step'),
          isTrue);
    });
  });
}
