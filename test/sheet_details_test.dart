import 'dart:async';
import 'dart:convert';

// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/core/session_guard.dart';
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
    checkoutGuard = SessionGuard();
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

    testWidgets('hands everything it knows over in one piece', (tester) async {
      final controller = build()..webView;

      await tester.pump();
      webView.controllers.first.post(
        jsonEncode(<String, Object?>{
          'type': 'ready',
          'amountMinor': 9742,
          'currency': 'USD',
        }),
      );

      expect(controller.snapshot.ready, isTrue);
      expect(controller.snapshot.amountMinor, 9742);
      expect(controller.snapshot.isComplete, isFalse);
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
        'closes rather than spinning for ever when your server throws while '
        'charging a saved card', (tester) async {
      final settled = await open(
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
      expect(find.text(r'Pay $97.42'), findsNothing);
      expect((await settled).code, CheckoutResultCode.outcomeUnknown);
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

    /*
     * A payer cannot go back to the methods mid-charge: that screen holds the saved card and
     * the wallet, a second payment one tap away. So the challenge always arrives on the card
     * screen, and takes the whole of it.
     */
    testWidgets('shows the issuer challenge, with no way back to the methods', (
      tester,
    ) async {
      await open(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(find.byTooltip(const PaymentSheetStrings().back), findsNothing);

      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });
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
      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });
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

  /*
   * The address the card is billed to is typed on the Flutter side, except the name, which
   * is a row of the card box. Neither reaches the gateway unless the box is told to ask for
   * one and the charge is told to carry the other.
   */
  group('the billing address', () {
    testWidgets('has the page put a name row in the box when it is collected',
        (tester) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
        collectsBilling: true,
        labels: const PaymentSheetStrings(nameOnCard: 'Nom sur la carte'),
      );

      webView.controllers.first.finishLoading();
      await tester.pump();

      expect(
        webView.controllers.first.scripts.last,
        contains('"collectName":true'),
      );
      expect(
        webView.controllers.first.scripts.last,
        contains('"nameLabel":"Nom sur la carte"'),
      );
      expect(
        webView.controllers.first.scripts.last,
        contains('"cardNumberLabel":"Card number"'),
      );
      controller.dispose();
    });

    testWidgets('leaves the box alone when it is not', (tester) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
      );

      webView.controllers.first.finishLoading();
      await tester.pump();

      expect(
        webView.controllers.first.scripts.last,
        contains('"collectName":false'),
      );
      controller.dispose();
    });

    testWidgets('travels with the charge', (tester) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
        collectsBilling: true,
      );

      webView.controllers.first.finishLoading();
      await tester.pump();

      for (final field in <String>['number', 'securityCode', 'expiry']) {
        webView.controllers.first.post(
          '{"type":"change","field":"$field","valid":true,"empty":false}',
        );
      }
      webView.controllers.first.post(
        '{"type":"ready","amountMinor":9742,"currency":"USD"}',
      );

      await controller.pay(
        billing: const BillingDetails(
          name: 'Ada Lovelace',
          address: '12 Noyes Street',
        ),
      );

      expect(
        webView.controllers.first.scripts.last,
        contains('"firstName":"Ada","lastName":"Lovelace"'),
      );
      controller.dispose();
    });
  });

  /*
   * Keeping a card needs the payer's explicit agreement, and the party that showed the
   * words is the only one that can evidence what was agreed to. So the row is PayLink's
   * SDK's to draw: all the sheet does is ask for it, and refuse to charge without it.
   */
  group('keeping the card', () {
    CardFieldsController keeping() => CardFieldsController(
          session: testFieldsSession(),
          pageUrl: testFieldsPageUrl,
          keepsTheCard: true,
        );

    Future<void> fillTheCard(
        WidgetTester tester, FakeWebViewController box) async {
      box.finishLoading();
      await tester.pump();

      for (final field in <String>['number', 'securityCode', 'expiry']) {
        box.post(
            '{"type":"change","field":"$field","valid":true,"empty":false}');
      }
      box.post('{"type":"ready","amountMinor":9742,"currency":"USD"}');
      await tester.pump();
    }

    testWidgets('has the page put the agreement in the box', (tester) async {
      final controller = keeping();

      webView.controllers.first.finishLoading();
      await tester.pump();

      expect(
        webView.controllers.first.scripts.last,
        contains('"collectConsent":true'),
      );
      controller.dispose();
    });

    testWidgets('will not charge a card the payer has not agreed to keep',
        (tester) async {
      final controller = keeping();
      final box = webView.controllers.first;

      await fillTheCard(tester, box);
      await controller.pay();

      expect(
        box.scripts.where((script) => script.contains('.pay(')),
        isEmpty,
        reason: 'the agreement is what makes this charge chargeable',
      );

      box.post(
          '{"type":"change","field":"consent","valid":true,"empty":false}');
      await tester.pump();
      await controller.pay();

      expect(box.scripts.last, contains('"tokenize":true'));
      controller.dispose();
    });
  });

  /*
   * A page served through a development tunnel, or from a staging origin behind a gate,
   * can need a header before it will hand the page over at all. Without one the web view
   * loads the gate's own page where the card fields should be.
   */
  group('the fields page headers', () {
    const headers = <String, String>{'ngrok-skip-browser-warning': 'true'};

    testWidgets('are sent with the card page', (tester) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
        pageHeaders: headers,
      );

      expect(controller.webView, isNotNull);
      await tester.pump();

      expect(webView.controllers.first.headers, headers);
      controller.dispose();
    });

    testWidgets('are sent with the wallet page too', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WalletSurface(
            session: testFieldsSession(),
            pageUrl: testFieldsPageUrl,
            wallet: PaymentWallet.googlePay,
            returnUrl: testReturnUrl,
            pageHeaders: headers,
            onComplete: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(webView.controllers.first.headers, headers);
    });

    testWidgets('are nothing at all when none were given', (tester) async {
      final controller = CardFieldsController(
        session: testFieldsSession(),
        pageUrl: testFieldsPageUrl,
      );

      expect(controller.webView, isNotNull);
      await tester.pump();

      expect(webView.controllers.first.headers, isEmpty);
      controller.dispose();
    });
  });
}
