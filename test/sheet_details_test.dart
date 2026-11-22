import 'dart:async';
import 'dart:convert';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sessions/deep_link.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'support/fake_launcher.dart';
import 'support/fake_webview.dart';
import 'support/fakes.dart';
import 'support/fixtures.dart';

/// The corners of the sheet: what it does with a retry, a back tap and a stray event.
void main() {
  late FakeWebViewPlatform webView;
  late FakeUrlLauncher launcher;
  late FakeDeepLinks links;

  setUp(() {
    webView = FakeWebViewPlatform.install();
    launcher = FakeUrlLauncher.install();
    links = FakeDeepLinks();
    returnLinkWatcher = ReturnLinkWatcher(source: links.source);
  });

  tearDown(() => links.dispose());

  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  group('CardFieldsController', () {
    CardFieldsController build() => CardFieldsController(
          session: testFieldsSession(),
          pageUrl: testFieldsPageUrl,
        );

    testWidgets('is not ready until the fields have mounted', (tester) async {
      final controller = build()..webView;

      await tester.pump();

      expect(controller.isReady, isFalse);
      expect(controller.isComplete, isFalse);

      webView.controllers.first.post(
        jsonEncode(<String, Object?>{
          'type': 'ready',
          'amountMinor': 9742.0,
          'currency': 'USD',
        }),
      );

      expect(controller.isReady, isTrue);
      // A gateway that prices in whole units still prices in minor ones.
      expect(controller.amountMinor, 9742);
      controller.dispose();
    });

    testWidgets('clears a stale message as the payer corrects the card',
        (tester) async {
      final controller = build()..webView;

      await tester.pump();

      final page = webView.controllers.first;

      page.post(jsonEncode(
          <String, Object?>{'type': 'error', 'code': 'card_invalid'}));

      expect(controller.errorMessage, isNull);

      page.post(
        jsonEncode(<String, Object?>{
          'type': 'change',
          'field': 'number',
          'valid': false,
          'empty': false,
        }),
      );
      page.post(jsonEncode(<String, Object?>{'type': 'charging'}));

      expect(controller.isCharging, isTrue);
      controller.dispose();
    });

    /// The wallet lives on its own surface, so a wallet event here is not this box's.
    testWidgets('ignores an event that belongs to the wallet', (tester) async {
      final controller = build()..webView;

      await tester.pump();

      webView.controllers.first.post(
        jsonEncode(<String, Object?>{
          'type': 'walletready',
          'paymentTypes': <String>['GOOGLEPAY'],
        }),
      );

      expect(controller.isReady, isFalse);
      controller.dispose();
    });

    testWidgets('will not charge a box that is not filled in', (tester) async {
      final controller = build()..webView;

      await tester.pump();
      await controller.pay();

      expect(
          webView.controllers.first.scripts.where((s) => s.contains('pay()')),
          isEmpty);
      controller.dispose();
    });
  });

  group('the sheet', () {
    PaymentSheetConfiguration configuration(
        {List<SavedCard> savedCards = const <SavedCard>[]}) {
      return PaymentSheetConfiguration(
        session: testFieldsSession(),
        fieldsPageUrl: testFieldsPageUrl,
        returnUrl: testReturnUrl,
        expectedInvoiceId: 90210,
        amountLabel: r'$97.42',
        wallets: const <PaymentWallet>[PaymentWallet.googlePay],
        savedCards: savedCards,
        chargeSavedCard: (_) async =>
            const CheckoutResult(status: CheckoutStatus.paid),
      );
    }

    Future<void> open(
        WidgetTester tester, PaymentSheetConfiguration config) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => GetPayInPaymentSheet.show(context, config),
              child: const Text('checkout'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('checkout'));
      await pumpFrames(tester);
    }

    testWidgets('keeps a retryable failure on the card form', (tester) async {
      await open(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);

      webView.controllers.first.post(
        jsonEncode(<String, Object?>{
          'type': 'error',
          'code': 'card_invalid',
          'message': 'That card number is not valid.',
        }),
      );
      await pumpFrames(tester);

      expect(find.text('That card number is not valid.'), findsOneWidget);
      expect(find.text(const PaymentSheetStrings().addNewCard), findsOneWidget);
    });

    testWidgets('comes back from the card form', (tester) async {
      await open(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(const PaymentSheetStrings().back));
      await pumpFrames(tester);

      expect(find.text(const PaymentSheetStrings().newPaymentMethod),
          findsOneWidget);
    });

    testWidgets('comes back from the card list', (tester) async {
      await open(
        tester,
        configuration(
          savedCards: const <SavedCard>[
            SavedCard(id: 'pm_1', last4: '7492'),
            SavedCard(id: 'pm_2', last4: '8216'),
          ],
        ),
      );

      await tester.tap(find.text('•••• 7492'));
      await pumpFrames(tester);

      expect(find.text(const PaymentSheetStrings().selectCard), findsOneWidget);

      await tester.tap(find.byTooltip(const PaymentSheetStrings().back));
      await pumpFrames(tester);

      expect(find.text(const PaymentSheetStrings().saved), findsOneWidget);
    });

    testWidgets('reports a sheet the payer swiped away as cancelled',
        (tester) async {
      late Future<CheckoutResult> pending;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  pending = GetPayInPaymentSheet.show(context, configuration()),
              child: const Text('checkout'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('checkout'));
      await pumpFrames(tester);

      // Tapping the barrier above the sheet is the payer walking away from it.
      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    testWidgets('hands the phone a link the wallet page cannot load itself',
        (tester) async {
      await open(tester, configuration());

      final wallet = webView.controllers.firstWhere(
        (controller) =>
            (controller.loaded.lastOrNull?.fragment ?? '').isNotEmpty,
      );

      final decision = await wallet.navigation!.onNavigationRequest!(
        const NavigationRequest(url: 'tel:+96512345678', isMainFrame: true),
      );

      expect(decision, NavigationDecision.prevent);
    });
  });

  /*
   * Seven tests written before the fixes they describe, from a review of the sheet. Each
   * one states what a payer should be able to do, and each failed before the change that
   * made it pass.
   */
  group('the sheet under duress', () {
    PaymentSheetConfiguration configuration({
      List<SavedCard> savedCards = const <SavedCard>[],
      Future<CheckoutResult> Function(SavedCard card)? chargeSavedCard,
      String origin = testOrigin,
    }) {
      return PaymentSheetConfiguration(
        session: testFieldsSession(origin: origin),
        fieldsPageUrl: testFieldsPageUrl,
        returnUrl: testReturnUrl,
        expectedInvoiceId: 90210,
        amountLabel: r'$97.42',
        wallets: const <PaymentWallet>[PaymentWallet.googlePay],
        savedCards: savedCards,
        chargeSavedCard: chargeSavedCard,
      );
    }

    Future<Future<CheckoutResult>> open(
      WidgetTester tester,
      PaymentSheetConfiguration config,
    ) async {
      final completer = Completer<CheckoutResult>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => completer
                  .complete(GetPayInPaymentSheet.show(context, config)),
              child: const Text('checkout'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('checkout'));
      await pumpFrames(tester);

      return completer.future;
    }

    void postToCard(Map<String, Object?> event) =>
        webView.controllers.first.post(jsonEncode(event));

    Future<void> completeTheCard(WidgetTester tester) async {
      postToCard(<String, Object?>{
        'type': 'ready',
        'amountMinor': 9742,
        'currency': 'USD',
      });

      for (final field in <String>['number', 'securityCode', 'expiry']) {
        postToCard(<String, Object?>{
          'type': 'change',
          'field': field,
          'valid': true,
          'empty': false,
        });
      }

      await pumpFrames(tester);
    }

    testWidgets(
        'sends the payer to the hosted checkout when the page is on the '
        'wrong origin', (tester) async {
      await open(
          tester, configuration(origin: 'https://elsewhere.example.com'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(launcher.launches.single.$1, testCheckoutUrl);
    });

    testWidgets(
        'lets the payer try again when your server throws while charging a '
        'saved card', (tester) async {
      await open(
        tester,
        configuration(
          savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
          chargeSavedCard: (_) async =>
              throw StateError('the network went away'),
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
          find.text(const PaymentSheetStrings().cardDeclined), findsOneWidget);
      expect(find.text(r'Pay $97.42'), findsOneWidget);
    });

    testWidgets(
        'says nothing to a sheet the payer closed while the charge was '
        'running', (tester) async {
      final release = Completer<CheckoutResult>();

      await open(
        tester,
        configuration(
          savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
          chargeSavedCard: (_) => release.future,
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      release.complete(
        const CheckoutResult(
            status: CheckoutStatus.notPaid, message: 'declined'),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('ignores what the page says after the card box is disposed', (
      tester,
    ) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
      );

      expect(controller.webView, isNotNull);
      await tester.pump();

      final page = webView.controllers.first;

      controller.dispose();
      page.post(jsonEncode(<String, Object?>{'type': 'charging'}));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(page.scripts.join(), contains('destroy'));
    });

    testWidgets(
        'shows the issuer challenge even when the payer went back first', (
      tester,
    ) async {
      await open(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(const PaymentSheetStrings().back));
      await pumpFrames(tester);

      postToCard(<String, Object?>{'type': 'authenticating'});
      await pumpFrames(tester);

      expect(find.text(const PaymentSheetStrings().newPaymentMethod),
          findsNothing);
      expect(find.byType(WebViewWidget), findsOneWidget);
    });

    testWidgets('keeps the challenge inside the screen when the keyboard is up',
        (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await open(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      postToCard(<String, Object?>{'type': 'authenticating'});
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('offers no saved card when every one of them has expired', (
      tester,
    ) async {
      await open(
        tester,
        configuration(
          savedCards: const <SavedCard>[
            SavedCard(
                id: 'pm_1', last4: '7492', expiryMonth: 1, expiryYear: 2020),
            SavedCard(
                id: 'pm_2', last4: '8216', expiryMonth: 2, expiryYear: 2021),
          ],
          chargeSavedCard: (_) async =>
              const CheckoutResult(status: CheckoutStatus.paid),
        ),
      );

      expect(find.text(const PaymentSheetStrings().saved), findsNothing);
      expect(find.textContaining('•••• '), findsNothing);
      expect(find.text(const PaymentSheetStrings().newCard), findsOneWidget);
    });
  });
}
