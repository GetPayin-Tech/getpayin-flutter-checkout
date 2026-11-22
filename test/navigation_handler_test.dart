import 'package:flutter_test/flutter_test.dart';
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
    );
  }

  late final CheckoutNavigationHandler handler;
  final List<CheckoutResult> results = <CheckoutResult>[];
  final List<String> external = <String>[];

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

    test('binds the result to the invoice the checkout was opened for', () {
      final harness = _Harness(expectedInvoiceId: 'INV-1');

      harness.navigate(returnLink('success=1&invoice_id=INV-ATTACKER'));

      expect(harness.results.single.status, CheckoutStatus.notPaid);
      expect(harness.results.single.code, CheckoutResultCode.wrongInvoice);
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
