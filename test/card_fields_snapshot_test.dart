import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/sheet/card_fields_snapshot.dart';
import 'package:getpayin_checkout/src/sheet/fields_protocol.dart';
import 'package:getpayin_checkout/src/sheet/fields_session.dart';

/// Every field the gateway has to render before a card can be charged.
CardFieldsSnapshot filledIn([CardFieldsSnapshot? from]) {
  var snapshot = from ?? const CardFieldsSnapshot();

  for (final field in <String>['number', 'securityCode', 'expiry']) {
    snapshot = applyFieldsEvent(
      snapshot,
      FieldsChanged(
          field: field, valid: true, empty: false, couldBeValid: true),
    );
  }

  return snapshot;
}

void main() {
  group('a box nobody has typed into', () {
    test('is not ready, and has nothing chargeable in it', () {
      const snapshot = CardFieldsSnapshot();

      expect(snapshot.ready, isFalse);
      expect(snapshot.isComplete, isFalse);
      expect(snapshot.amountMinor, isNull);
      expect(snapshot.errorMessage, isNull);
    });
  });

  group('applyFieldsEvent', () {
    test('takes the price the gateway mounted with', () {
      final snapshot = applyFieldsEvent(
        const CardFieldsSnapshot(),
        const FieldsReady(amountMinor: 9742, currency: 'USD'),
      );

      expect(snapshot.ready, isTrue);
      expect(snapshot.amountMinor, 9742);
      expect(snapshot.currency, 'USD');
    });

    test('is chargeable only once every field holds something and it is live',
        () {
      final typed = filledIn();

      expect(typed.isComplete, isFalse,
          reason: 'the fields have not mounted yet');

      final live = applyFieldsEvent(
        typed,
        const FieldsReady(amountMinor: 9742, currency: 'USD'),
      );

      expect(live.isComplete, isTrue);
    });

    test('is no longer chargeable when a field stops being valid', () {
      final live = filledIn(
        applyFieldsEvent(
          const CardFieldsSnapshot(),
          const FieldsReady(amountMinor: 9742, currency: 'USD'),
        ),
      );

      final corrected = applyFieldsEvent(
        live,
        const FieldsChanged(
          field: 'number',
          valid: false,
          empty: false,
          couldBeValid: true,
        ),
      );

      expect(corrected.isComplete, isFalse);
    });

    /// A payer correcting a card should not still be reading why the last one failed.
    test('clears the last message as the payer corrects a field', () {
      final refused = applyFieldsEvent(
        const CardFieldsSnapshot(),
        const FieldsError(
            failure: FieldsFailure.cardInvalid, message: 'No good'),
      );

      expect(refused.errorMessage, 'No good');

      final correcting = applyFieldsEvent(
        refused,
        const FieldsChanged(
          field: 'number',
          valid: false,
          empty: false,
          couldBeValid: true,
        ),
      );

      expect(correcting.errorMessage, isNull);
    });

    test('keeps the message while the field is still empty', () {
      final refused = applyFieldsEvent(
        const CardFieldsSnapshot(),
        const FieldsError(
            failure: FieldsFailure.cardInvalid, message: 'No good'),
      );

      final untouched = applyFieldsEvent(
        refused,
        const FieldsChanged(
          field: 'number',
          valid: false,
          empty: true,
          couldBeValid: true,
        ),
      );

      expect(untouched.errorMessage, 'No good');
    });

    test('marks the two steps a charge goes through', () {
      final charging = applyFieldsEvent(
        const CardFieldsSnapshot(),
        const FieldsCharging(),
      );
      final authenticating = applyFieldsEvent(
        charging,
        const FieldsAuthenticating(),
      );

      expect(authenticating.charging, isTrue);
      expect(authenticating.authenticating, isTrue);
    });

    test('ends both the moment the charge answers', () {
      final answered = applyFieldsEvent(
        applyFieldsEvent(
          applyFieldsEvent(const CardFieldsSnapshot(), const FieldsCharging()),
          const FieldsAuthenticating(),
        ),
        const FieldsPayment(success: true),
      );

      expect(answered.charging, isFalse);
      expect(answered.authenticating, isFalse);
    });

    test('ends both on a failure too, and says what it was', () {
      final failed = applyFieldsEvent(
        applyFieldsEvent(const CardFieldsSnapshot(), const FieldsCharging()),
        const FieldsError(
          failure: FieldsFailure.authenticationFailed,
          message: 'The bank refused it.',
        ),
      );

      expect(failed.charging, isFalse);
      expect(failed.authenticating, isFalse);
      expect(failed.errorMessage, 'The bank refused it.');
    });

    /// The wallet lives on its own surface, so its events say nothing about this box.
    test('is left exactly as it was by a wallet event', () {
      final live = filledIn();

      expect(
        identical(
            live, applyFieldsEvent(live, const FieldsWalletReady(<String>[]))),
        isTrue,
      );
      expect(
        identical(live, applyFieldsEvent(live, const FieldsWalletError())),
        isTrue,
      );
    });
  });

  /*
   * The name is typed into the card box, because a box whose rows are drawn by two engines
   * cannot be kept aligned, but what counts as a name is decided here: the charge wants two
   * of them and ignores the whole address without both.
   */
  group('the name on the card', () {
    test('is remembered, so the sheet can bill the card to it', () {
      final snapshot = applyFieldsEvent(
        const CardFieldsSnapshot(ready: true),
        const FieldsChanged(
          field: 'name',
          valid: false,
          empty: false,
          couldBeValid: true,
          value: ' Ada Lovelace ',
        ),
      );

      expect(snapshot.cardholderName, 'Ada Lovelace');
    });

    test('counts as filled in only once it is two names', () {
      CardFieldsSnapshot typed(String name) => applyFieldsEvent(
            const CardFieldsSnapshot(
              ready: true,
              valid: <String>{'number', 'securityCode', 'expiry'},
            ),
            FieldsChanged(
              field: 'name',
              valid: false,
              empty: name.isEmpty,
              couldBeValid: true,
              value: name,
            ),
          );

      expect(typed('Ada').valid, isNot(contains('name')));
      expect(typed('Ada Lovelace').valid, contains('name'));
    });
  });
}
