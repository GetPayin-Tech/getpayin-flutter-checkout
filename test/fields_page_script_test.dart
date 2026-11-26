@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/fields_page_runner.dart';

/*
 * The card page is JavaScript the integrator hosts, and its rules are the sheet's rules: what
 * it puts on a message is what the sheet trusts. These run the page's own script under Node,
 * so they check what it does rather than what its text says.
 */
void main() {
  const started = '''
host.start({
  clientToken: 'tok',
  sdkUrl: 'https://pay.example.com/sdk/paylink-fields-v1.js',
  pageKey: 'key'
});
await tick();
await tick();
await tick();
''';

  Iterable<Map<String, Object?>> errors(List<Map<String, Object?>> posted) =>
      posted.where((message) => message['type'] == 'error');

  group('a charge', skip: skipWithoutNode, () {
    test('ends with its own code, even after another charge started', () async {
      final posted = await runFieldsPage('''
$started
host.pay({ attempt: 'first' });
await tick();
host.pay({ attempt: 'second' });
await tick();
sdk.pays[0].reject({ code: 'authentication_failed', message: 'late' });
await tick();
''');

      expect(
        errors(posted).single['attempt'],
        'first',
        reason: "the first charge's failure must not end the second one",
      );
    });

    test('answers with its own code', () async {
      final posted = await runFieldsPage('''
$started
host.pay({ attempt: 'first' });
await tick();
sdk.pays[0].resolve({ success: true, invoiceId: 90210, paidStatus: 'PAID' });
await tick();
''');

      expect(
        posted
            .singleWhere((message) => message['type'] == 'payment')['attempt'],
        'first',
      );
    });

    test('is not ended by an error the SDK reports on its own', () async {
      final posted = await runFieldsPage('''
$started
host.pay({ attempt: 'first' });
await tick();
sdk.handlers.error({ code: 'card_invalid', message: 'event' });
await tick();
''');

      expect(
        errors(posted).single.containsKey('attempt'),
        isFalse,
        reason: 'only the charge itself may say how the charge ended',
      );
    });
  });

  group('the wallet page', skip: skipWithoutNode, () {
    const reportAddress = '''
process.stdout.write(JSON.stringify({ type: 'address', hash: location.hash }) + '\\n');
''';

    String? addressAfter(List<Map<String, Object?>> posted) =>
        posted.singleWhere((message) => message['type'] == 'address')['hash']
            as String?;

    test('says on its address that it refused the SDK it was sent', () async {
      final posted = await runFieldsPage(
        'await tick();\n$reportAddress',
        hash: '#t=tok&s=https%3A%2F%2Fevil.example%2Fsdk.js&w=googlepay',
      );

      expect(addressAfter(posted), 'paylink-wallet-unavailable');
    });

    test('says so when the wallet cannot be shown', () async {
      final posted = await runFieldsPage(
        '''
await tick();
await tick();
await tick();
sdk.handlers.walleterror({ message: 'no wallet on this phone' });
$reportAddress''',
        hash:
            '#t=tok&s=https%3A%2F%2Fpay.example.com%2Fsdk%2Fpaylink-fields-v1.js'
            '&w=googlepay',
      );

      expect(addressAfter(posted), 'paylink-wallet-unavailable');
    });

    test('says nothing of a wallet error once its button is up', () async {
      final posted = await runFieldsPage(
        '''
await tick();
await tick();
await tick();
sdk.handlers.walletready({ paymentTypes: ['GOOGLEPAY'] });
sdk.handlers.walleterror({ message: 'the payer closed the wallet' });
$reportAddress''',
        hash:
            '#t=tok&s=https%3A%2F%2Fpay.example.com%2Fsdk%2Fpaylink-fields-v1.js'
            '&w=googlepay',
      );

      expect(addressAfter(posted), isNot('paylink-wallet-unavailable'));
    });

    /*
     * A wallet payment can get the issuer's 3-D Secure check, which PayLink's SDK draws over
     * the whole page. The wallet row is a button's height, so the page says on its address
     * when the check is up and when it has gone, and the host makes room for it.
     */
    group('with a bank check', () {
      const walletHash =
          '#t=tok&s=https%3A%2F%2Fpay.example.com%2Fsdk%2Fpaylink-fields-v1.js'
          '&w=googlepay';
      const buttonUp = '''
await tick();
await tick();
await tick();
sdk.handlers.walletready({ paymentTypes: ['GOOGLEPAY'] });
''';

      test('says on its address when the check is up', () async {
        final posted = await runFieldsPage(
          "${buttonUp}sdk.handlers.authenticating({ stage: 'challenge' });\n"
          '$reportAddress',
          hash: walletHash,
        );

        expect(addressAfter(posted), 'paylink-challenge');
      });

      test('says on its address when the check ends with no charge', () async {
        final posted = await runFieldsPage(
          "${buttonUp}sdk.handlers.authenticating({ stage: 'challenge' });\n"
          "sdk.handlers.walleterror({ message: 'verification not completed' });\n"
          '$reportAddress',
          hash: walletHash,
        );

        expect(addressAfter(posted), 'paylink-challenge-ended');
      });

      test('marks its charge once the check is passed', () async {
        final posted = await runFieldsPage(
          "${buttonUp}sdk.handlers.authenticating({ stage: 'challenge' });\n"
          'sdk.handlers.charging();\n'
          '$reportAddress',
          hash: walletHash,
        );

        expect(addressAfter(posted), 'paylink-charging');
      });

      test('says nothing when the bank asked for no check', () async {
        final posted = await runFieldsPage(
          "${buttonUp}sdk.handlers.authenticating({ stage: 'setup' });\n"
          "sdk.handlers.walleterror({ message: 'the payer closed the wallet' });\n"
          '$reportAddress',
          hash: walletHash,
        );

        expect(addressAfter(posted), walletHash);
      });
    });

    test('leaves the card page alone, which has no wallet to start', () async {
      final posted = await runFieldsPage('await tick();\n$reportAddress');

      expect(addressAfter(posted), '');
    });
  });

  test('fails a charge asked for before its fields are up',
      skip: skipWithoutNode, () async {
    final posted = await runFieldsPage('''
host.pay({ attempt: 'first' });
await tick();
''');

    expect(
      errors(posted).single['attempt'],
      'first',
      reason: 'a page that says nothing leaves the sheet waiting for good',
    );
  });

  test('puts the key it was handed on every message', skip: skipWithoutNode,
      () async {
    final posted = await runFieldsPage('''
$started
sdk.handlers.charging();
host.pay({ attempt: 'first' });
await tick();
sdk.pays[0].resolve({ success: false, message: 'Declined' });
await tick();
''');

    expect(posted, isNotEmpty);
    expect(posted.map((message) => message['pageKey']), everyElement('key'));
  });
}
