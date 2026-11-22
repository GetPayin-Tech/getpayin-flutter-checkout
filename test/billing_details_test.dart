import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

/*
 * Microform's token carries no billing, so what the payer types beside the card is the only
 * address the charge can be matched against. The gateway wants it as two names, and asks
 * for the region under a name that depends on the country.
 */
void main() {
  group('BillingDetails.toWire', () {
    test('gives the gateway the shape it reads', () {
      const billing = BillingDetails(
        name: 'Ada Lovelace',
        country: 'us',
        state: 'NY',
        city: 'New York',
        address: '12 Noyes Street',
        postalCode: '10013',
      );

      expect(billing.toWire(), <String, Object?>{
        'firstName': 'Ada',
        'lastName': 'Lovelace',
        'country': 'US',
        'state': 'NY',
        'city': 'New York',
        'address': '12 Noyes Street',
        'postalCode': '10013',
      });
    });

    test('reads everything after the first name as the surname', () {
      const billing = BillingDetails(name: '  Ada  King  Lovelace ');

      expect(billing.toWire()['firstName'], 'Ada');
      expect(billing.toWire()['lastName'], 'King Lovelace');
    });

    const unusable = <String, String?>{
      'a name of one word': 'Ada',
      'a blank name': '   ',
      'no name at all': null,
    };

    unusable.forEach((label, name) {
      test('sends nothing for $label, which the charge would ignore anyway',
          () {
        expect(BillingDetails(name: name, city: 'Cairo').toWire(), isEmpty);
      });
    });

    test('leaves out what the payer did not fill in', () {
      const billing = BillingDetails(name: 'Ada Lovelace', city: '  ');

      expect(billing.toWire(), <String, Object?>{
        'firstName': 'Ada',
        'lastName': 'Lovelace',
      });
    });
  });

  group('BillingDetails.isComplete', () {
    test('wants a name and a street before it is worth sending', () {
      expect(const BillingDetails(name: 'Ada Lovelace').isComplete, isFalse);
      expect(
        const BillingDetails(name: 'Ada Lovelace', address: '12 Noyes Street')
            .isComplete,
        isTrue,
      );
    });
  });
}
