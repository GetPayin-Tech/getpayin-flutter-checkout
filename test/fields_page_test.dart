import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sheet/fields_page.dart'
    show paylinkSdkUrl, walletChargingFragment;

import 'support/fixtures.dart';

void main() {
  final html = buildFieldsPageHtml(
    sdkUrl: 'https://pay.example.com/sdk/paylink-fields-v1.js',
  );

  group('buildFieldsPageHtml', () {
    test('loads the SDK from PayLink and nothing else', () {
      expect(
        html,
        contains('"https://pay.example.com/sdk/paylink-fields-v1.js"'),
      );
      expect(html, contains('PayLink.fields('));
    });

    /*
     * The host is written in as the one to fall back on, not as the only one. A page is
     * hosted once and the payment says which PayLink it belongs to, so a sheet pointed at
     * another environment does not need the page regenerated for it.
     */
    test('takes the SDK address the host gives it over its own', () {
      expect(html, contains('var DEFAULT_SDK ='));
      expect(html, contains('loadSdk(config.sdkUrl)'));
      expect(
        html,
        isNot(contains('<script src=')),
        reason:
            'a written-in tag is the thing that pins the page to one PayLink',
      );
    });

    /*
     * The wallet page reads its configuration from its own link, and anyone can send a payer
     * a link to the page on your origin. A script address taken from that link unchecked
     * would run the sender's script as your site.
     */
    test('loads a script its own link names only when it was made for it', () {
      expect(
        html,
        contains(
          'var KNOWN_SDKS = ["https://pay.example.com/sdk/paylink-fields-v1.js"];',
        ),
      );
      expect(html, contains("knownSdk(hash.get('s'))"));
      expect(html, isNot(contains("hash.get('s') ||")));
    });

    test('knows every PayLink it was made for, by address and path', () {
      final page = buildFieldsPageHtml(
        sdkUrl: 'https://pay.example.com/sdk/paylink-fields-v1.js?v=2',
        otherSdkUrls: const <String>[
          'https://test.example.com/sdk/paylink-fields-v1.js',
        ],
      );

      expect(
        page,
        contains(
          'var KNOWN_SDKS = ["https://pay.example.com/sdk/paylink-fields-v1.js",'
          '"https://test.example.com/sdk/paylink-fields-v1.js"];',
        ),
      );
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

    /*
     * The wallet surface has no channel, so the page says its charge is out the only way an
     * unscripted page can: on its own address, which the host watches.
     */
    test('marks its own address once a wallet charge is out', () {
      // That it does so on the SDK's `charging` event, and after a bank check too, is run
      // in fields_page_script_test.dart.
      expect(html, contains('var CHARGING = "$walletChargingFragment";'));
      expect(html, contains('window.location.hash = CHARGING;'));
    });

    /*
     * A row is laid out with its own display rule, and an author's display rule beats the
     * browser's for `hidden`. Without one of its own, the name row the page keeps hidden
     * still takes a row of the box, and the sheet sizes the box for the rows it asked for,
     * so the last row, expiry and security code, falls out of view.
     */
    test('keeps a row it hides out of the box', () {
      expect(html, contains('id="name-row" hidden'));
      expect(html, contains('.row[hidden] { display: none; }'));
    });

    /*
     * The sheet gives the box one hairline between each pair of rows it shows. A divider
     * drawn under a hidden row as well makes the box a pixel taller than that, and the web
     * view crops its bottom edge.
     */
    test('draws a divider only between rows it shows', () {
      expect(html, contains('.row:not([hidden]) ~ .row {'));
      expect(html, isNot(contains('.row + .row')));
    });

    test('answers a charge with the code it was sent', () {
      expect(html, contains('attempt: asked.attempt'));
    });

    test('carries no secret of its own', () {
      expect(html.toLowerCase(), isNot(contains('hash_token')));
      expect(html.toLowerCase(), isNot(contains('signature')));
    });
  });

  group('the SDK addresses the page will load', () {
    test('are written the way the page writes them back', () {
      final page = buildFieldsPageHtml(
        sdkUrl: 'https://pay.example.test//sdk/paylink-fields-v1.js',
        otherSdkUrls: const <String>['https://dev.example.test'],
      );

      expect(
        page,
        contains('"https://pay.example.test/sdk/paylink-fields-v1.js"'),
        reason: 'a host given with a trailing slash doubles the one before sdk',
      );
      expect(
        page,
        contains('"https://dev.example.test/"'),
        reason: 'URL reports no path as a slash, so this side has to as well',
      );
    });
  });

  group('paylinkSdkUrl', () {
    test('names the SDK on a PayLink host, with or without a closing slash',
        () {
      expect(
        paylinkSdkUrl('https://pay.example.com/'),
        'https://pay.example.com/sdk/paylink-fields-v1.js',
      );
      expect(
        paylinkSdkUrl('https://pay.example.com'),
        'https://pay.example.com/sdk/paylink-fields-v1.js',
      );
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
