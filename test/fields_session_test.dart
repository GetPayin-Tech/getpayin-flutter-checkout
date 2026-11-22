import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('PayLinkFieldsSession.fromInit', () {
    test('reads what /init answered for a fields payment', () {
      final session = PayLinkFieldsSession.fromInit(testInitResponse())!;

      expect(session.clientToken, 'eyJpdiI6ZXhhbXBsZQ');
      expect(
          session.sdkUrl, 'https://pay.example.com/sdk/paylink-fields-v1.js');
      expect(session.origin, testOrigin);
      expect(session.checkoutUrl, testCheckoutUrl);
      expect(session.invoiceId, 90210);
    });

    /*
     * A server that forwards "the payment" to its app sends one or the other, and neither
     * is wrong.
     */
    test('takes the data block on its own as readily as the whole envelope',
        () {
      final data = testInitResponse()['data']! as Map<String, Object?>;

      expect(PayLinkFieldsSession.fromInit(data)?.clientToken, isNotNull);
    });

    test('is nothing when the payment carries no fields block', () {
      expect(
        PayLinkFieldsSession.fromInit(<String, Object?>{
          'data': <String, Object?>{'checkout_url': testCheckoutUrl},
        }),
        isNull,
      );
    });

    test('is nothing when the fields block is missing a part of the session',
        () {
      final response = testInitResponse();
      final data = response['data']! as Map<String, Object?>;

      (data['fields']! as Map<String, Object?>).remove('client_token');

      expect(PayLinkFieldsSession.fromInit(response), isNull);
    });

    test('reads the expiry the client token carries', () {
      final session = PayLinkFieldsSession.fromInit(
        testInitResponse(expiresAt: '2020-01-01T00:00:00.000000Z'),
      )!;

      expect(session.hasExpired, isTrue);
    });

    test('has not expired when nothing said when it would', () {
      expect(testFieldsSession().hasExpired, isFalse);
    });
  });

  group('the registered origin', () {
    /*
     * The origin is baked into the capture context CyberSource issues and checked on every
     * call, so a page served from anywhere else renders no fields at all. Checking it turns
     * that silence into something an integrator can read.
     */
    test('accepts a page served from it, whatever the path', () {
      final session = testFieldsSession();

      expect(session.servesFrom(testFieldsPageUrl), isTrue);
      expect(session.servesFrom('$testOrigin/elsewhere/fields.html'), isTrue);
    });

    test('refuses another host, another scheme, and an unparseable page', () {
      final session = testFieldsSession();

      expect(
          session.servesFrom('https://evil.example.com/fields.html'), isFalse);
      expect(
          session.servesFrom('http://shop.example.com/fields.html'), isFalse);
      expect(session.servesFrom('not a url'), isFalse);
    });
  });

  group('FieldsFailure', () {
    const fatal = <String>[
      'fields_unavailable',
      'fields_unsupported',
      'session_invalid',
      'origin_not_allowed',
      'library_unavailable',
      'payments_paused',
    ];

    for (final code in fatal) {
      test('$code sends the payer to the hosted checkout', () {
        expect(FieldsFailure.fromCode(code).sendsPayerToHostedCheckout, isTrue);
      });
    }

    const retryable = <String>[
      'card_invalid',
      'expiry_invalid',
      'authentication_failed',
      'authentication_abandoned',
      'already_mounted',
      'in_progress',
    ];

    for (final code in retryable) {
      test('$code is about this attempt alone', () {
        expect(
            FieldsFailure.fromCode(code).sendsPayerToHostedCheckout, isFalse);
      });
    }

    /*
     * A code this package has not heard of is a code whose consequences it cannot reason
     * about, and the hosted checkout always works.
     */
    test('a code it does not know is fatal rather than retried', () {
      expect(FieldsFailure.fromCode('something_new'), FieldsFailure.unknown);
      expect(FieldsFailure.fromCode(null).sendsPayerToHostedCheckout, isTrue);
    });

    test('is matched without regard to case or stray space', () {
      expect(FieldsFailure.fromCode(' Session_Invalid '),
          FieldsFailure.sessionInvalid);
    });
  });
}
