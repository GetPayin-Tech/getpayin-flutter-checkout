import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout_example/saved_card_charge.dart';

/// The harness's server hands on PayLink's answer to a token charge with a 200, whatever
/// PayLink said, so only the answer's own `success` tells a charge from a decline.
void main() {
  test('a decline is not paid, though it came with a 200', () {
    final result = readSavedCardCharge(<String, Object?>{
      'success': false,
      'message': 'The card was declined.',
      'reason_code': '203',
      'authenticated': false,
    });

    expect(result.status, CheckoutStatus.notPaid);
    expect(result.code, isNull);
    expect(result.message, 'The card was declined.');
  });

  test('a charge that went through is paid, and names its invoice', () {
    final result = readSavedCardCharge(<String, Object?>{
      'success': true,
      'data': <String, Object?>{
        'invoice_id': 4521,
        'invoice_number': 'INV-4521',
        'paid_status': 'PAID',
        'card_token': 'tok_1',
      },
      'authenticated': false,
    });

    expect(result.status, CheckoutStatus.paid);
    expect(result.invoiceId, '4521');
    expect(result.invoiceStatus, 'PAID');
  });

  test('an answer that is neither a charge nor a decline cannot be confirmed',
      () {
    final result = readSavedCardCharge(<String, Object?>{
      'message': 'Server Error',
      'authenticated': false,
    });

    expect(result.status, CheckoutStatus.notPaid);
    expect(result.code, CheckoutResultCode.outcomeUnknown);
  });

  test('a charge that names no invoice cannot be confirmed', () {
    final result = readSavedCardCharge(<String, Object?>{
      'success': true,
      'authenticated': false,
    });

    expect(result.status, CheckoutStatus.notPaid);
    expect(result.code, CheckoutResultCode.outcomeUnknown);
  });

  /*
   * The bank check comes back on a return link the harness's server writes. When it could
   * not tell how the charge ended, that link carries no result at all.
   */
  group('a bank check', () {
    CheckoutResult endingOn(String query) => readSavedCardChallenge(
          readCheckoutResult('myapp://payment-return?$query'),
        );

    test('that ended on a link with no result cannot be confirmed', () {
      final result = endingOn(
        'message=PayLink+answered+500%3A+the+card+may+have+been+charged',
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
    });

    test('that was declined is still a decline', () {
      final result = endingOn(
        'success=0&invoice_id=4521&invoice_status=UNPAID&message=Declined',
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, isNull);
      expect(result.message, 'Declined');
    });

    test('that paid is still paid', () {
      final result = endingOn(
        'success=1&invoice_id=4521&invoice_status=PAID&message=Charged',
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, '4521');
    });
  });
}
