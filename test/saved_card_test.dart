import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

void main() {
  group('SavedCard', () {
    test('is not expired when nothing said when it would be', () {
      expect(const SavedCard(id: 'pm_1', last4: '7492').hasExpired, isFalse);
    });

    /// A card is good to the last day of the month printed on it.
    test('counts the month on the card as still good', () {
      final now = DateTime.now();

      expect(
        SavedCard(
          id: 'pm_1',
          last4: '7492',
          expiryMonth: now.month,
          expiryYear: now.year,
        ).hasExpired,
        isFalse,
      );
    });

    test('knows a card whose month has passed', () {
      expect(
        const SavedCard(
                id: 'pm_1', last4: '7492', expiryMonth: 1, expiryYear: 2020)
            .hasExpired,
        isTrue,
      );
    });

    test('needs both halves of the expiry before it decides', () {
      expect(
        const SavedCard(id: 'pm_1', last4: '7492', expiryYear: 2020).hasExpired,
        isFalse,
      );
    });
  });

  group('CardBrand.fromName', () {
    const names = <String, CardBrand>{
      'visa': CardBrand.visa,
      'VISA': CardBrand.visa,
      'mastercard': CardBrand.mastercard,
      'master-card': CardBrand.mastercard,
      'mc': CardBrand.mastercard,
      'amex': CardBrand.amex,
      'American Express': CardBrand.amex,
      'discover': CardBrand.discover,
      'unionpay': CardBrand.unionPay,
      'cup': CardBrand.unionPay,
      'mada': CardBrand.mada,
      'something else': CardBrand.unknown,
    };

    names.forEach((name, brand) {
      test('reads "$name" as ${brand.label}', () {
        expect(CardBrand.fromName(name), brand);
      });
    });

    test('reads nothing at all as an unknown network', () {
      expect(CardBrand.fromName(null), CardBrand.unknown);
    });
  });

  group('PaymentWallet.forPlatform', () {
    test('offers the wallet that belongs on the phone', () {
      const both = <PaymentWallet>[
        PaymentWallet.applePay,
        PaymentWallet.googlePay
      ];

      expect(PaymentWallet.forPlatform('ios', both), PaymentWallet.applePay);
      expect(
          PaymentWallet.forPlatform('android', both), PaymentWallet.googlePay);
    });

    /*
     * One wallet per payment: a charge is booked under the first wallet its capture context
     * offered, not the one the payer picked.
     */
    test('offers nothing when none of them belongs on this phone', () {
      expect(
        PaymentWallet.forPlatform(
            'ios', const <PaymentWallet>[PaymentWallet.googlePay]),
        isNull,
      );
      expect(PaymentWallet.forPlatform('macos', PaymentWallet.values), isNull);
      expect(PaymentWallet.forPlatform('android', const <PaymentWallet>[]),
          isNull);
    });
  });
}
