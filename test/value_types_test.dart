import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/core/url.dart';

import 'support/fixtures.dart';

void main() {
  group('CheckoutResult', () {
    const paid = CheckoutResult(
      status: CheckoutStatus.paid,
      invoiceId: '4512',
      invoiceStatus: 'PAID',
      message: 'Payment completed',
      returnUrl: testReturnUrl,
    );

    test('compares and hashes by value, so two reports of one payment are one',
        () {
      const same = CheckoutResult(
        status: CheckoutStatus.paid,
        invoiceId: '4512',
        invoiceStatus: 'PAID',
        message: 'Payment completed',
        returnUrl: testReturnUrl,
      );

      final both = <CheckoutResult>[paid, same];

      expect(paid, same);
      expect(paid.hashCode, same.hashCode);
      expect(both.toSet(), hasLength(1));
    });

    test('separates results that differ in any field', () {
      expect(
        paid,
        isNot(const CheckoutResult(
            status: CheckoutStatus.paid, invoiceId: '4513')),
      );
      expect(paid, isNot(const CheckoutResult(status: CheckoutStatus.notPaid)));
      expect(paid, isNot('not a result'));
    });

    test('answers isPaid only for a paid result', () {
      expect(paid.isPaid, isTrue);
      expect(
          const CheckoutResult(status: CheckoutStatus.notPaid).isPaid, isFalse);
      expect(const CheckoutResult(status: CheckoutStatus.cancelled).isPaid,
          isFalse);
    });

    /// A result goes into bug reports and logs, so it has to read as itself.
    test('describes itself without the raw link', () {
      final described = paid.toString();

      expect(described, contains('paid'));
      expect(described, contains('4512'));
      expect(described, contains('PAID'));
    });

    test(
        'carries the code through a downgrade and keeps the facts about the link',
        () {
      final downgraded = paid.downgradedTo(
        CheckoutStatus.notPaid,
        code: CheckoutResultCode.wrongInvoice,
        message: 'another invoice',
      );

      expect(downgraded.status, CheckoutStatus.notPaid);
      expect(downgraded.code, CheckoutResultCode.wrongInvoice);
      expect(downgraded.message, 'another invoice');
      expect(downgraded.invoiceId, '4512');
      expect(downgraded.invoiceStatus, 'PAID');
      expect(downgraded.returnUrl, testReturnUrl);
      expect(downgraded.toString(), contains('wrong_invoice'));
    });
  });

  group('the wire names', () {
    test('match what GetPayIn and the other SDKs use', () {
      expect(CheckoutStatus.paid.wireName, 'paid');
      expect(CheckoutStatus.notPaid.wireName, 'not_paid');
      expect(CheckoutStatus.cancelled.wireName, 'cancelled');
      expect(CheckoutResultCode.unreadableReturnLink.wireName,
          'unreadable_return_link');
      expect(CheckoutResultCode.wrongInvoice.wireName, 'wrong_invoice');
      expect(
        CheckoutResultCode.unexpectedInvoiceStatus.wireName,
        'unexpected_invoice_status',
      );
      expect(CheckoutPresentation.inApp.wireName, 'in-app');
      expect(CheckoutPresentation.browser.wireName, 'browser');
    });
  });

  group('ParsedUrl', () {
    test('compares and hashes by value', () {
      final left = parseUrl(testReturnUrl);
      final right = parseUrl('$testReturnUrl/');

      expect(left, right);
      expect(left.hashCode, right?.hashCode);
      expect(left, isNot(parseUrl('otherapp://payment-return')));
      expect(left, isNot('myapp://payment-return'));
    });

    test('describes itself for a diagnostic', () {
      expect(
          parseUrl('https://pay.getpayin.com/checkout/abc?x=1').toString(),
          '''
ParsedUrl(scheme: https, authority: pay.getpayin.com, path: /checkout/abc, query: x=1)'''
              .trim());
    });
  });

  group('CheckoutWebViewSettings', () {
    test('compares and hashes by value', () {
      const ios = CheckoutWebViewSettings(
          javaScriptEnabled: true, applePayEnabled: true);

      expect(buildCheckoutWebViewSettings('ios'), ios);
      expect(buildCheckoutWebViewSettings('ios').hashCode, ios.hashCode);
      expect(buildCheckoutWebViewSettings('android'), isNot(ios));
      expect(ios, isNot('settings'));
    });

    test('describes which wallet it turned on', () {
      expect(
        buildCheckoutWebViewSettings('android').toString(),
        contains('paymentRequestEnabled: true'),
      );
    });
  });
}
