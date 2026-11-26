import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/webview/load_failure.dart';

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

  /*
   * iOS reports a load it stopped as a failure: one bank redirect replacing another during
   * 3-D Secure, or a navigation the checkout itself refused. Read as the page failing, it
   * would put an error over a payment that is still going.
   */
  group('isInterruptedLoad', () {
    test('is a load the web view cancelled', () {
      expect(isInterruptedLoad(-999), isTrue);
    });

    test('is a load interrupted by a navigation the checkout refused', () {
      expect(isInterruptedLoad(102), isTrue);
    });

    test('is not a load that failed', () {
      expect(isInterruptedLoad(-1), isFalse);
      expect(isInterruptedLoad(-1009), isFalse);
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
