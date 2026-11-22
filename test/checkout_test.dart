import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';
import 'package:getpayin_flutter_checkout/src/sessions/browser_session.dart';
import 'package:getpayin_flutter_checkout/src/sessions/registry.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  late List<CheckoutRequest> presented;
  late CheckoutPresenter presenter;

  setUp(() {
    presented = <CheckoutRequest>[];
    presenter = (request) async {
      presented.add(request);

      return const CheckoutResult(
          status: CheckoutStatus.paid, invoiceId: 'INV-1');
    };
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    unregisterPresenter(presenter);
    debugDefaultTargetPlatformOverride = null;
  });

  group('GetPayInCheckout.presentationFor', () {
    test('uses the app screen on iOS', () {
      expect(GetPayInCheckout.presentationFor(), CheckoutPresentation.inApp);
    });

    test('uses the browser sheet on Android before Google approves the app',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(GetPayInCheckout.presentationFor(), CheckoutPresentation.browser);
    });

    test('uses the app screen on Android once googlePayInApp is on', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(
        GetPayInCheckout.presentationFor(googlePayInApp: true),
        CheckoutPresentation.inApp,
      );
    });

    test('honours an explicit override', () {
      expect(
        GetPayInCheckout.presentationFor(
            override: CheckoutPresentation.browser),
        CheckoutPresentation.browser,
      );
    });
  });

  group('GetPayInCheckout.open', () {
    const badCheckoutUrls = <String>['myapp://checkout', 'not a url', ''];

    for (final url in badCheckoutUrls) {
      test('refuses the checkout URL "$url"', () async {
        await expectLater(
          GetPayInCheckout.open(
              url, const OpenCheckoutOptions(returnUrl: testReturnUrl)),
          throwsA(isA<GetPayInConfigError>()),
        );
        expect(GetPayInCheckout.busy, isFalse);
      });
    }

    test('refuses a return link with no scheme', () async {
      await expectLater(
        GetPayInCheckout.open(
          testCheckoutUrl,
          const OpenCheckoutOptions(returnUrl: 'payment-return'),
        ),
        throwsA(isA<GetPayInConfigError>()),
      );
    });

    const badInvoiceIds = <(String, Object)>[
      ('an empty', ''),
      ('a boolean', true),
      ('a fractional', 45.12),
    ];

    for (final (label, invoiceId) in badInvoiceIds) {
      test('refuses $label expectedInvoiceId before opening anything',
          () async {
        registerPresenter(presenter);

        await expectLater(
          GetPayInCheckout.open(
            testCheckoutUrl,
            OpenCheckoutOptions(
                returnUrl: testReturnUrl, expectedInvoiceId: invoiceId),
          ),
          throwsA(isA<GetPayInConfigError>()),
        );

        expect(presented, isEmpty);
        expect(GetPayInCheckout.busy, isFalse);
      });
    }

    test('asks the mounted provider to present an in-app checkout', () async {
      registerPresenter(presenter);

      final result = await GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(
            returnUrl: testReturnUrl, title: 'Pay for Gold Plan'),
      );

      expect(result.invoiceId, 'INV-1');
      expect(presented.single.checkoutUrl, testCheckoutUrl);
      expect(presented.single.options.title, 'Pay for Gold Plan');
    });

    test('hands the provider the validated checkout URL, not the raw one',
        () async {
      registerPresenter(presenter);

      await GetPayInCheckout.open(
        '  $testCheckoutUrl  ',
        const OpenCheckoutOptions(returnUrl: testReturnUrl),
      );

      expect(presented.single.checkoutUrl, testCheckoutUrl);
    });

    test('explains that the provider is missing rather than failing obscurely',
        () async {
      await expectLater(
        GetPayInCheckout.open(
          testCheckoutUrl,
          const OpenCheckoutOptions(returnUrl: testReturnUrl),
        ),
        throwsA(isA<GetPayInProviderMissingError>()),
      );
      expect(GetPayInCheckout.busy, isFalse);
    });

    test('uses the browser sheet on Android and leaves the provider alone',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      registerPresenter(presenter);

      final phone = FakePhone(
        onOpened: (phone) =>
            phone.deliver(returnLink('success=1&invoice_id=INV-7')),
      );

      browserCheckoutPorts = phone.ports;

      final result = await GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(returnUrl: testReturnUrl),
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, 'INV-7');
      expect(phone.opened, <String>[testCheckoutUrl]);
      expect(presented, isEmpty);
    });

    test(
        'refuses a second checkout while one is open, and frees the slot after',
        () async {
      final release = Completer<CheckoutResult>();

      presenter = (request) => release.future;
      registerPresenter(presenter);

      final first = GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(returnUrl: testReturnUrl),
      );

      expect(GetPayInCheckout.busy, isTrue);

      await expectLater(
        GetPayInCheckout.open(
          testCheckoutUrl,
          const OpenCheckoutOptions(returnUrl: testReturnUrl),
        ),
        throwsA(isA<GetPayInSessionBusyError>()),
      );

      release.complete(const CheckoutResult(status: CheckoutStatus.paid));
      await first;

      expect(GetPayInCheckout.busy, isFalse);
    });

    test('frees the slot after a failed checkout', () async {
      presenter = (request) async => throw StateError('boom');
      registerPresenter(presenter);

      await expectLater(
        GetPayInCheckout.open(
          testCheckoutUrl,
          const OpenCheckoutOptions(returnUrl: testReturnUrl),
        ),
        throwsStateError,
      );
      expect(GetPayInCheckout.busy, isFalse);
    });
  });
}
