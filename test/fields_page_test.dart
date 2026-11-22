import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

import 'support/fixtures.dart';

void main() {
  final html = buildFieldsPageHtml(
    sdkUrl: 'https://pay.example.com/sdk/paylink-fields-v1.js',
  );

  group('buildFieldsPageHtml', () {
    test('loads the SDK from PayLink and nothing else', () {
      expect(html,
          contains('src="https://pay.example.com/sdk/paylink-fields-v1.js"'));
      expect(html, contains('PayLink.fields('));
    });

    test('mounts the two fields the gateway has to render, and no more', () {
      expect(html, contains("number: '#number'"));
      expect(html, contains("securityCode: '#cvc'"));
      expect(html, contains('id="expiry"'));
    });

    test('answers the host over the channel the sheet listens on', () {
      expect(html, contains(fieldsChannelName));
      expect(html, contains('postMessage'));
    });

    /*
     * The page waits to be told. A token in the page's URL reaches the host's access log,
     * the web view's history and any Referer the page sends.
     */
    test('starts inert, and is handed its token by the host', () {
      expect(html, contains('window.__paylinkHost'));
      expect(html, contains('start: function'));
    });

    test(
        'takes its configuration from the fragment only for the wallet surface',
        () {
      expect(html, contains('window.location.hash'));
      expect(html, contains('window.location.href = result.returnUrl'));
    });

    test('carries no secret of its own', () {
      expect(html.toLowerCase(), isNot(contains('hash_token')));
      expect(html.toLowerCase(), isNot(contains('signature')));
    });
  });

  group('walletPageUrl', () {
    final url = walletPageUrl(
      pageUrl: testFieldsPageUrl,
      clientToken: 'tok_123',
      wallets: const <String>['APPLEPAY'],
    );

    test('keeps the token out of the part a server would log', () {
      expect(url.split('#').first, testFieldsPageUrl);
      expect(url, contains('#t=tok_123'));
      expect(url, contains('w=APPLEPAY'));
    });

    test('replaces a fragment the page URL already had', () {
      expect(
        walletPageUrl(
          pageUrl: '$testFieldsPageUrl#stale',
          clientToken: 'tok_123',
          wallets: const <String>[],
        ),
        '$testFieldsPageUrl#t=tok_123',
      );
    });
  });

  /*
   * The page is something the integrator hosts, so the repository carries a copy they can
   * take. Two copies of a payment page drift, so the copy is checked against the builder.
   */
  group('the copy at doc/paylink-fields.html', () {
    test('is what the builder writes, with the host left to fill in', () {
      final committed = File('doc/paylink-fields.html').readAsStringSync();

      expect(
        committed,
        buildFieldsPageHtml(
            sdkUrl: '<YOUR-PAYLINK-HOST>/sdk/paylink-fields-v1.js'),
      );
    });
  });
}
