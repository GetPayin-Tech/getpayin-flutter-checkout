import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

void main() {
  group('parseFieldsEvent', () {
    test('reads the gateway price the fields mounted with', () {
      final event = parseFieldsEvent(
          '{"type":"ready","amountMinor":9742,"currency":"USD"}');

      expect(event, isA<FieldsReady>());
      expect((event! as FieldsReady).amountMinor, 9742);
      expect((event as FieldsReady).currency, 'USD');
    });

    test('reads one field changing', () {
      final event = parseFieldsEvent(
        '{"type":"change","field":"number","valid":true,'
        '"empty":false,"couldBeValid":true}',
      )! as FieldsChanged;

      expect(event.field, 'number');
      expect(event.valid, isTrue);
      expect(event.empty, isFalse);
    });

    test('reads the two steps a charge goes through', () {
      expect(parseFieldsEvent('{"type":"authenticating"}'),
          isA<FieldsAuthenticating>());
      expect(parseFieldsEvent('{"type":"charging"}'), isA<FieldsCharging>());
    });

    test('reads what the charge answered', () {
      final event = parseFieldsEvent(
        '{"type":"payment","success":true,"message":"Approved",'
        '"reasonCode":"100","invoiceId":90210,"paidStatus":"PAID",'
        '"returnUrl":"https://shop.example.com/thanks"}',
      )! as FieldsPayment;

      expect(event.success, isTrue);
      expect(event.invoiceId, 90210);
      expect(event.paidStatus, 'PAID');
      expect(event.reasonCode, '100');
    });

    test('reads a failure as the code the sheet decides on', () {
      final event = parseFieldsEvent(
              '{"type":"error","code":"session_invalid","message":"gone"}')!
          as FieldsError;

      expect(event.failure, FieldsFailure.sessionInvalid);
      expect(event.message, 'gone');
    });

    test('reads the wallet saying it is ready, and saying it is not', () {
      final ready = parseFieldsEvent(
              '{"type":"walletready","paymentTypes":["APPLEPAY"]}')!
          as FieldsWalletReady;

      expect(ready.paymentTypes, <String>['APPLEPAY']);
      expect(
          parseFieldsEvent('{"type":"walleterror"}'), isA<FieldsWalletError>());
    });

    /*
     * The page is the only thing that posts here, but a malformed message must not take a
     * payment screen down: it is no event at all.
     */
    const unreadable = <String>[
      'not json',
      '[]',
      '"a string"',
      '{"type":"something-else"}',
      '{}',
    ];

    for (final raw in unreadable) {
      test('ignores ${jsonEncode(raw)}', () {
        expect(parseFieldsEvent(raw), isNull);
      });
    }
  });

  group('resultFromPayment', () {
    test('reports a paid invoice the charge was opened for', () {
      final result = resultFromPayment(
        const FieldsPayment(
            success: true, invoiceId: 90210, paidStatus: 'PAID'),
        expectedInvoiceId: 90210,
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, '90210');
    });

    test('refuses a charge booked against another invoice', () {
      final result = resultFromPayment(
        const FieldsPayment(success: true, invoiceId: 5001, paidStatus: 'PAID'),
        expectedInvoiceId: 90210,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.wrongInvoice);
    });

    /*
     * The same rule the return link goes through: an authorised or part-paid invoice is not
     * an order to fulfil.
     */
    test('refuses a success whose invoice is not paid in full', () {
      final result = resultFromPayment(
        const FieldsPayment(
            success: true, invoiceId: 90210, paidStatus: 'AUTHORIZED'),
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.unexpectedInvoiceStatus);
    });

    test('keeps the reason the payer was given for a decline', () {
      final result = resultFromPayment(
        const FieldsPayment(
            success: false, message: 'Card declined', invoiceId: 90210),
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, 'Card declined');
      expect(result.code, isNull);
    });

    /*
     * A return link is the artefact a server checks the signature of, so when the page hands
     * one back that reads as GetPayIn's own, it is what settles the payment.
     */
    test('prefers a readable return link over the message beside it', () {
      final result = resultFromPayment(
        FieldsPayment(
          success: true,
          paidStatus: 'PAID',
          invoiceId: 90210,
          returnUrl:
              returnLink('success=0&invoice_id=90210&message=Card+declined'),
        ),
        expectedInvoiceId: 90210,
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.message, 'Card declined');
    });

    test('settles on the message when the link carries no fields to read', () {
      final result = resultFromPayment(
        const FieldsPayment(
          success: true,
          paidStatus: 'PAID',
          invoiceId: 90210,
          returnUrl: 'https://shop.example.com/thanks',
        ),
        expectedInvoiceId: 90210,
      );

      expect(result.status, CheckoutStatus.paid);
    });
  });

  group('the commands the host sends', () {
    test('hands the token over the channel rather than in the page URL', () {
      final command = startFieldsCommand(
        clientToken: 'tok_123',
        style: const <String, Object?>{'border': '#e6e6e6'},
        wallets: const <String>['GOOGLEPAY'],
      );

      expect(command, contains('window.__paylinkHost'));
      expect(command, contains('tok_123'));
      expect(command, contains('GOOGLEPAY'));
      expect(command, contains('#e6e6e6'));
    });

    /*
     * The expiry is read by the page from its own input, which sits in the box with the two
     * hosted fields so the three cannot drift out of alignment.
     */
    /*
     * The page is hosted once and the payment says which PayLink it belongs to, so the host
     * tells it where the SDK lives rather than the page deciding when it was generated. A
     * page pinned to one environment and a token minted on another is an error that names
     * the wrong system entirely.
     */
    test('tells the page where its SDK lives', () {
      final command = startFieldsCommand(
        clientToken: 'abc',
        style: const <String, Object?>{},
        sdkUrl: 'https://devpay.example.com/sdk/paylink-fields-v1.js',
      );

      expect(
        command,
        contains(
          '"sdkUrl":"https://devpay.example.com/sdk/paylink-fields-v1.js"',
        ),
      );
    });

    test('reads the name the page holds, which the sheet bills the card to',
        () {
      final event = parseFieldsEvent(
        '{"type":"change","field":"name","empty":false,"value":"Ada Lovelace"}',
      );

      expect(event, isA<FieldsChanged>());
      expect((event! as FieldsChanged).field, 'name');
      expect((event as FieldsChanged).value, 'Ada Lovelace');
    });

    test('reads no value from a field the gateway hosts', () {
      final event = parseFieldsEvent(
        '{"type":"change","field":"number","valid":true,"empty":false}',
      );

      expect((event! as FieldsChanged).value, isNull);
    });

    test('asks for a charge without carrying the expiry', () {
      expect(payCommand(),
          'window.__paylinkHost && window.__paylinkHost.pay(null);');
    });

    /*
     * The address does carry, because the page has none to give: the gateway's token holds
     * no billing, and the form the payer filled in is on the Flutter side of the sheet.
     */
    test('carries the billing address the payer gave', () {
      const billing = BillingDetails(
        name: 'Ada Lovelace',
        country: 'EG',
        city: 'Cairo',
        address: '12 Noyes Street',
      );

      expect(
        payCommand(billing: billing),
        'window.__paylinkHost && window.__paylinkHost.pay('
        '{"billing":{"firstName":"Ada","lastName":"Lovelace","country":"EG",'
        '"city":"Cairo","address":"12 Noyes Street"}});',
      );
    });

    /*
     * Keeping the card is asked for here and agreed to on the page: the wording belongs to
     * PayLink's own SDK, so all the sheet can do is say that this charge means to keep it.
     */
    test('asks for the card to be kept, without claiming the agreement', () {
      expect(
        payCommand(keepTheCard: true),
        'window.__paylinkHost && window.__paylinkHost.pay({"tokenize":true});',
      );
    });

    test('carries nothing for an address the charge would ignore', () {
      expect(
        payCommand(billing: const BillingDetails(city: 'Cairo')),
        'window.__paylinkHost && window.__paylinkHost.pay(null);',
      );
    });
  });

  /*
   * A line per event, for the diagnostic a tester pastes into a report. It says what
   * happened and never what was typed: the name on the card is the payer's, and a trace
   * that carries it is a trace nobody can safely send anywhere.
   */
  group('describeFieldsEvent', () {
    test('says what the box reported, and what it is worth', () {
      expect(
        describeFieldsEvent(
          const FieldsReady(amountMinor: 9742, currency: 'USD'),
        ),
        'ready 9742 USD',
      );
      expect(
        describeFieldsEvent(const FieldsCharging()),
        'charging',
      );
      expect(
        describeFieldsEvent(const FieldsAuthenticating(stage: 'challenge')),
        'authenticating challenge',
      );
    });

    test('names a field without repeating it back', () {
      final line = describeFieldsEvent(
        const FieldsChanged(
          field: 'name',
          valid: true,
          empty: false,
          couldBeValid: true,
          value: 'Ada Lovelace',
        ),
      );

      expect(line, 'change name valid');
      expect(line, isNot(contains('Ada')));
    });

    test('carries a failure in full, which is the one thing worth having', () {
      expect(
        describeFieldsEvent(
          const FieldsError(
            failure: FieldsFailure.originNotAllowed,
            message: 'The card fields page is not served from the origin.',
          ),
        ),
        'error origin_not_allowed: The card fields page is not served from the origin.',
      );
    });

    test('says what the wallet did, which the card box never reports', () {
      expect(
        describeFieldsEvent(
          const FieldsWalletReady(<String>['GOOGLEPAY']),
        ),
        'wallet ready GOOGLEPAY',
      );
      expect(
        describeFieldsEvent(const FieldsWalletError(message: 'No wallet.')),
        'wallet error: No wallet.',
      );
      expect(
        describeFieldsEvent(const FieldsWalletError()),
        'wallet error',
      );
    });

    test('says how a charge answered', () {
      expect(
        describeFieldsEvent(
          const FieldsPayment(
            success: false,
            message: 'Declined.',
            reasonCode: '201',
            invoiceId: 90210,
            paidStatus: 'UNPAID',
            returnUrl: 'myapp://payment-return?success=0',
          ),
        ),
        'payment declined 201 invoice 90210 UNPAID: Declined.',
      );
    });
  });
}
