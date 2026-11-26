import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/core/intent_link.dart';
import 'package:getpayin_checkout/src/core/navigation.dart';

import 'support/fixtures.dart';

void main() {
  const context = NavigationContext(returnUrl: testReturnUrl, isTopFrame: true);

  /*
   * A bank's 3-D Secure step on Android can be an `intent:` link, which no app answers to
   * as written. Chrome reads it as the app link it names, and its web page for when no app
   * takes that. Both go through the rules every other link does.
   */
  group('readIntentTargets', () {
    test('reads the app link an intent link names', () {
      final targets = readIntentTargets(
        'intent://auth/3ds?ref=1#Intent;scheme=mybank;package=com.bank;end',
        context,
      );

      expect(targets?.app, 'mybank://auth/3ds?ref=1');
    });

    test('reads the web page to fall back on', () {
      final targets = readIntentTargets(
        'intent://auth#Intent;scheme=mybank;'
        'S.browser_fallback_url=https%3A%2F%2Fbank.example%2F3ds%3Fref%3D1;end',
        context,
      );

      expect(targets?.web, 'https://bank.example/3ds?ref=1');
    });

    test('refuses an app the checkout may not open', () {
      for (final scheme in <String>['sms', 'market', 'myapp', 'intent']) {
        expect(
          readIntentTargets('intent://x#Intent;scheme=$scheme;end', context)
              ?.app,
          isNull,
          reason: '$scheme is not a bank app',
        );
      }
    });

    test('refuses a fallback that is not a web page', () {
      for (final fallback in <String>[
        'javascript%3Aalert(1)',
        'myapp%3A%2F%2Fpayment-return%3Fsuccess%3D1',
        '%2Frelative',
        '%E0%A4%A',
        'https%3A%2F%2Fbank.example%2Fp%E9ge',
        '%FF',
        'https%3A%2F%2F%5B%3A%3A1%2F',
      ]) {
        expect(
          readIntentTargets(
            'intent://x#Intent;scheme=mybank;S.browser_fallback_url=$fallback;end',
            context,
          )?.web,
          isNull,
          reason: fallback,
        );
      }
    });

    test('finds nothing in an intent link with no details', () {
      final targets = readIntentTargets('intent://scan', context);

      expect(targets, isNotNull);
      expect(targets?.app, isNull);
      expect(targets?.web, isNull);
    });

    test('is not asked about any other link', () {
      expect(readIntentTargets('mybank://auth', context), isNull);
      expect(readIntentTargets('https://bank.example/3ds', context), isNull);
    });
  });
}
