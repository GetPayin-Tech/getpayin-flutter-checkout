import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/src/webview/load_failure.dart';

import 'support/fixtures.dart';

void main() {
  group('isMainFrameFailure', () {
    test('is the page when the web view says so', () {
      expect(isMainFrameFailure(true), isTrue);
    });

    test('is not the page when the web view says a frame failed', () {
      expect(isMainFrameFailure(false), isFalse);
    });

    /*
     * iOS reports navigation failures only, which are the page by definition, and leaves
     * the field unset. Read as a frame, a failed checkout page would show the payer a
     * working-looking blank screen instead of the error.
     */
    test('is the page when the web view does not say', () {
      expect(isMainFrameFailure(null), isTrue);
    });
  });

  group('isPageHttpFailure', () {
    test('is the page when the failing request is the page the payer is on',
        () {
      expect(
        isPageHttpFailure(failedUri: testCheckoutUrl, pageUri: testCheckoutUrl),
        isTrue,
      );
    });

    test('ignores the query, which a redirected checkout rewrites', () {
      expect(
        isPageHttpFailure(
            failedUri: '$testCheckoutUrl?step=2', pageUri: testCheckoutUrl),
        isTrue,
      );
    });

    /*
     * An HTTP error is reported for every request a page makes. A third-party script
     * answering 404 must not blank out a checkout that loaded.
     */
    test('is not the page when some other request failed', () {
      expect(
        isPageHttpFailure(
          failedUri: 'https://analytics.example/collect',
          pageUri: testCheckoutUrl,
        ),
        isFalse,
      );
    });

    test('is not the page when either side is unknown', () {
      expect(isPageHttpFailure(failedUri: null, pageUri: testCheckoutUrl),
          isFalse);
      expect(isPageHttpFailure(failedUri: testCheckoutUrl, pageUri: null),
          isFalse);
    });
  });
}
