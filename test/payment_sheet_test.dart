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
import 'package:getpayin_checkout/src/sheet/sheet_parts.dart';
import 'package:getpayin_checkout/src/webview/wallet_settings.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'support/fake_launcher.dart';
import 'support/fake_webview.dart';
import 'support/fakes.dart';
import 'support/fixtures.dart';

/// The sheet, driven the way the page drives it.
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

  tearDown(() async {
    declareHostAppSchemes(const <String>[]);
    await links.dispose();
  });

  /// Pumps the frames a sheet transition needs, without waiting for a spinner to stop.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  PaymentSheetConfiguration configuration({
    List<PaymentWallet> wallets = const <PaymentWallet>[
      PaymentWallet.googlePay
    ],
    List<SavedCard> savedCards = const <SavedCard>[],
    Future<CheckoutResult> Function(SavedCard card)? chargeSavedCard,
    bool fallBackToHostedCheckout = true,
    bool collectBillingAddress = false,
    void Function(FieldsError error)? onHandover,
    void Function(String note)? onDiagnostic,
    Duration successPause = Duration.zero,
    String origin = testOrigin,
    Object? expectedInvoiceId = 90210,
  }) {
    return PaymentSheetConfiguration(
      collectBillingAddress: collectBillingAddress,
      onHandover: onHandover,
      onDiagnostic: onDiagnostic,
      successPause: successPause,
      session: testFieldsSession(origin: origin),
      fieldsPageUrl: testFieldsPageUrl,
      returnUrl: testReturnUrl,
      expectedInvoiceId: expectedInvoiceId,
      amountLabel: r'$97.42',
      wallets: wallets,
      savedCards: savedCards,
      chargeSavedCard: chargeSavedCard,
      fallBackToHostedCheckout: fallBackToHostedCheckout,
    );
  }

  /// A sheet with a saved card whose charge answers only when the test says so.
  PaymentSheetConfiguration slowSavedCard(
    Completer<CheckoutResult> answer, {
    Duration successPause = Duration.zero,
  }) {
    return PaymentSheetConfiguration(
      session: testFieldsSession(),
      fieldsPageUrl: testFieldsPageUrl,
      returnUrl: testReturnUrl,
      expectedInvoiceId: 90210,
      amountLabel: r'$97.42',
      successPause: successPause,
      wallets: const <PaymentWallet>[PaymentWallet.googlePay],
      savedCards: const <SavedCard>[
        SavedCard(id: 'pm_1', last4: '7492'),
        SavedCard(id: 'pm_2', last4: '8216'),
      ],
      chargeSavedCard: (_) => answer.future,
    );
  }

  /// Opens the sheet over an app, and hands back what it will settle with.
  Future<Future<CheckoutResult>> openSheet(
    WidgetTester tester,
    PaymentSheetConfiguration config, {
    bool withProvider = false,
  }) async {
    final completer = Completer<CheckoutResult>();
    final page = Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            completer.complete(GetPayInPaymentSheet.show(context, config)),
        child: const Text('checkout'),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: withProvider ? GetPayInProvider(child: page) : page),
    );
    await tester.tap(find.text('checkout'));
    await pumpFrames(tester);

    return completer.future;
  }

  /// The controller behind the card box, which is the first one the sheet builds.
  FakeWebViewController cardBox() => webView.controllers.first;

  /// The controller behind the wallet button, which loads a URL carrying a fragment.
  ///
  /// The newest one: the sheet replaces the surface after a decline, and the fake keeps
  /// every controller it ever built, so the oldest match is the one that already answered.
  FakeWebViewController walletSurface() => webView.controllers.lastWhere(
        (controller) =>
            (controller.loaded.lastOrNull?.fragment ?? '').isNotEmpty,
      );

  void postToCard(Map<String, Object?> event) =>
      cardBox().post(jsonEncode(event));

  /// The code the card box sent with its last charge, which the answer has to carry.
  String chargeCode() {
    final pay =
        cardBox().scripts.lastWhere((script) => script.contains('.pay('));

    return RegExp(r'"attempt":"([0-9a-f]+)"').firstMatch(pay)!.group(1)!;
  }

  /// Answers the card box's last charge the way its own page does.
  void answerTheCharge(Map<String, Object?> payment) => postToCard(
        <String, Object?>{
          'type': 'payment',
          ...payment,
          'attempt': chargeCode(),
        },
      );

  /// Fails the card box's last charge the way its own page does.
  void failTheCharge(Map<String, Object?> error) => postToCard(
        <String, Object?>{
          'type': 'error',
          ...error,
          'attempt': chargeCode(),
        },
      );

  Future<void> completeTheCard(WidgetTester tester) async {
    postToCard(<String, Object?>{
      'type': 'ready',
      'amountMinor': 9742,
      'currency': 'USD'
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

  testWidgets('lays the payment out the way a payer expects a sheet to look', (
    tester,
  ) async {
    final strings = const PaymentSheetStrings();

    await openSheet(
      tester,
      configuration(
        savedCards: const <SavedCard>[
          SavedCard(id: 'pm_1', last4: '7492', brand: CardBrand.mastercard),
          SavedCard(id: 'pm_2', last4: '8216', brand: CardBrand.visa),
        ],
      ),
    );

    expect(find.text(strings.orPayUsing), findsOneWidget);
    expect(find.text(strings.saved), findsOneWidget);
    expect(find.text('•••• 7492'), findsOneWidget);
    expect(find.text(strings.viewMore), findsOneWidget);
    expect(find.text(strings.newPaymentMethod), findsOneWidget);
    expect(find.text(strings.newCard), findsOneWidget);
    expect(find.text(r'Pay $97.42'), findsOneWidget);
  });

  testWidgets('opens the full card list from the saved row', (tester) async {
    await openSheet(
      tester,
      configuration(
        savedCards: const <SavedCard>[
          SavedCard(id: 'pm_1', last4: '7492'),
          SavedCard(id: 'pm_2', last4: '8216'),
        ],
      ),
    );

    await tester.tap(find.text(const PaymentSheetStrings().viewMore));
    await pumpFrames(tester);

    expect(find.text(const PaymentSheetStrings().selectCard), findsOneWidget);
    expect(find.text('•••• 8216'), findsOneWidget);

    await tester.tap(find.text('•••• 8216'));
    await pumpFrames(tester);

    expect(find.text(const PaymentSheetStrings().saved), findsOneWidget);
    expect(find.text('•••• 8216'), findsOneWidget);
  });

  testWidgets('charges a saved card through your own server', (tester) async {
    final charged = <String>[];
    final pending = await openSheet(
      tester,
      configuration(
        savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
        chargeSavedCard: (card) async {
          charged.add(card.id);

          return const CheckoutResult(
            status: CheckoutStatus.paid,
            invoiceId: '90210',
            invoiceStatus: 'PAID',
          );
        },
      ),
    );

    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);

    expect(charged, <String>['pm_1']);
    expect((await pending).status, CheckoutStatus.paid);
  });

  /*
   * A saved card's answer is a claim of payment like the return link's and the fields'. A
   * charge on a token makes its own invoice, though, so it is held to what it says about
   * that invoice, not to the one the sheet was opened for.
   */
  group("a saved card's answer", () {
    Future<CheckoutResult> payWithSavedCard(
      WidgetTester tester,
      CheckoutResult answer,
    ) async {
      final pending = await openSheet(
        tester,
        configuration(
          savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
          chargeSavedCard: (_) async => answer,
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('is refused when the invoice it names is not paid',
        (tester) async {
      final result = await payWithSavedCard(
        tester,
        const CheckoutResult(
          status: CheckoutStatus.paid,
          invoiceId: '90211',
          invoiceStatus: 'UNPAID',
        ),
      );

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.unexpectedInvoiceStatus);
    });

    testWidgets('is not held to the invoice the sheet opened for',
        (tester) async {
      final result = await payWithSavedCard(
        tester,
        const CheckoutResult(
          status: CheckoutStatus.paid,
          invoiceId: '90211',
          invoiceStatus: 'PAID',
        ),
      );

      expect(result.status, CheckoutStatus.paid);
      expect(result.invoiceId, '90211');
    });
  });

  testWidgets('takes a new card and settles on what PayLink answered',
      (tester) async {
    final pending = await openSheet(tester, configuration());

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);

    expect(find.text(const PaymentSheetStrings().addNewCard), findsOneWidget);

    await completeTheCard(tester);

    // The gateway priced the payment, so the button says what will actually be charged.
    expect(find.text(r'Pay $97.42'), findsOneWidget);

    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);

    expect(cardBox().scripts.last, contains('__paylinkHost.pay({"attempt":'));

    answerTheCharge(<String, Object?>{
      'success': true,
      'invoiceId': 90210,
      'paidStatus': 'PAID',
    });
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.paid);
    expect(result.invoiceId, '90210');
  });

  /*
   * `/init` already said which invoice this payment is for, so an app that leaves
   * `expectedInvoiceId` out still has its results held to that one.
   */
  testWidgets('holds a result to the invoice the session names when given none',
      (tester) async {
    final pending =
        await openSheet(tester, configuration(expectedInvoiceId: null));

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    await completeTheCard(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);
    answerTheCharge(<String, Object?>{
      'success': true,
      'invoiceId': 4444,
      'paidStatus': 'PAID',
    });
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.notPaid);
    expect(result.code, CheckoutResultCode.wrongInvoice);
  });

  testWidgets('takes a payment when the session names no readable invoice',
      (tester) async {
    final pending = await openSheet(
      tester,
      PaymentSheetConfiguration(
        session:
            PayLinkFieldsSession.fromInit(testInitResponse(invoiceId: ''))!,
        fieldsPageUrl: testFieldsPageUrl,
        returnUrl: testReturnUrl,
        amountLabel: r'$97.42',
        successPause: Duration.zero,
      ),
    );

    CheckoutResult? settled;

    unawaited(pending.then((result) => settled = result));

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    await completeTheCard(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);
    answerTheCharge(<String, Object?>{
      'success': true,
      'invoiceId': 90210,
      'paidStatus': 'PAID',
    });
    await pumpFrames(tester);

    expect(
      settled?.status,
      CheckoutStatus.paid,
      reason: 'an id nobody can read binds the payment to no invoice at all',
    );
  });

  testWidgets('refuses an expected invoice that is not one before it opens',
      (tester) async {
    Object? refused;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => GetPayInPaymentSheet.show(
              context,
              configuration(expectedInvoiceId: ''),
            ).then((_) {}, onError: (Object error) {
              refused = error;
            }),
            child: const Text('checkout'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('checkout'));
    await pumpFrames(tester);

    expect(refused, isA<GetPayInConfigError>());
    expect(find.byType(GetPayInPaymentSheet), findsNothing);
    expect(checkoutGuard.busy, isFalse);
  });

  testWidgets('refuses a return link that is not one before it opens',
      (tester) async {
    Object? refused;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => GetPayInPaymentSheet.show(
              context,
              PaymentSheetConfiguration(
                session: testFieldsSession(),
                fieldsPageUrl: testFieldsPageUrl,
                returnUrl: 'not a link',
              ),
            ).then((_) {}, onError: (Object error) {
              refused = error;
            }),
            child: const Text('checkout'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('checkout'));
    await pumpFrames(tester);

    expect(
      refused,
      isA<GetPayInConfigError>(),
      reason: 'a wallet answer would never match it, and the fallback throws',
    );
    expect(find.byType(GetPayInPaymentSheet), findsNothing);
  });

  testWidgets(
      'refuses a session whose checkout link is not one before it opens',
      (tester) async {
    final init = testInitResponse();

    (init['data']! as Map<String, Object?>)['checkout_url'] =
        'myapp://not-a-checkout';

    Object? refused;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => GetPayInPaymentSheet.show(
              context,
              PaymentSheetConfiguration(
                session: PayLinkFieldsSession.fromInit(init)!,
                fieldsPageUrl: testFieldsPageUrl,
                returnUrl: testReturnUrl,
              ),
            ).then((_) {}, onError: (Object error) {
              refused = error;
            }),
            child: const Text('checkout'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('checkout'));
    await pumpFrames(tester);

    expect(
      refused,
      isA<GetPayInConfigError>(),
      reason: 'the hosted fallback would throw after the sheet had closed',
    );
  });

  /*
   * A token in the page's URL reaches the host's access log, the web view's history and any
   * Referer the page sends. It is handed over the channel instead.
   */
  testWidgets('never puts the client token in the card page URL',
      (tester) async {
    await openSheet(tester, configuration());

    cardBox().finishLoading();
    await pumpFrames(tester);

    final loaded = cardBox().loaded.single.toString();

    expect(loaded, testFieldsPageUrl);
    expect(loaded, isNot(contains('eyJpdiI6')));
    expect(cardBox().scripts.join(), contains('eyJpdiI6'));
  });

  /*
   * WebKit turns Apple Pay off on any page the host app has scripted, so the one surface
   * that shows a wallet is the one surface that is never scripted.
   */
  testWidgets('leaves the wallet surface unscripted', (tester) async {
    await openSheet(tester, configuration());

    expect(walletSurface().channels, isEmpty);
    expect(walletSurface().scripts, isEmpty);
    expect(walletSurface().loaded.single.fragment, contains('t='));
  });

  testWidgets('takes the wallet away when its page says it cannot be shown',
      (tester) async {
    final notes = <String>[];

    await openSheet(tester, configuration(onDiagnostic: notes.add));
    walletSurface().changeUrl('$testFieldsPageUrl#paylink-wallet-unavailable');
    await pumpFrames(tester);

    expect(
      find.byType(WalletSurface),
      findsNothing,
      reason: 'an empty row where a wallet should be helps nobody',
    );
    expect(notes, contains(startsWith('wallet unavailable')));
  });

  testWidgets('keeps the sheet open on a decline, with the reason',
      (tester) async {
    await openSheet(tester, configuration());

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    await completeTheCard(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);

    answerTheCharge(<String, Object?>{
      'success': false,
      'invoiceId': 90210,
      'message': 'Card declined',
    });
    await pumpFrames(tester);

    expect(find.text('Card declined'), findsOneWidget);
    expect(find.text(const PaymentSheetStrings().addNewCard), findsOneWidget);
  });

  testWidgets('clears a wallet decline once the next wallet charge is out',
      (tester) async {
    declareHostAppSchemes(const <String>['myapp']);

    await openSheet(tester, configuration());
    await walletSurface().navigate(
      returnLink('success=0&invoice_id=90210&message=Declined'),
    );
    await pumpFrames(tester);

    expect(find.text('Declined'), findsOneWidget);

    walletSurface().changeUrl('$testFieldsPageUrl#paylink-charging');
    await pumpFrames(tester);

    expect(find.text('Declined'), findsNothing);
  });

  testWidgets('clears the reason for a decline once the payer pays again',
      (tester) async {
    await openSheet(tester, configuration());

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    await completeTheCard(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);
    answerTheCharge(<String, Object?>{
      'success': false,
      'invoiceId': 90210,
      'message': 'Card declined',
    });
    await pumpFrames(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);

    expect(
      find.text('Card declined'),
      findsNothing,
      reason: 'left up during the next charge, it reads as that one failing',
    );
  });

  testWidgets('sends a payment the fields cannot take to the hosted checkout', (
    tester,
  ) async {
    await openSheet(tester, configuration(), withProvider: true);

    postToCard(<String, Object?>{'type': 'error', 'code': 'session_invalid'});
    await pumpFrames(tester);
    await pumpFrames(tester);

    // This phone is an Android one, so the hosted checkout is the browser sheet.
    expect(launcher.launches.single.$1, testCheckoutUrl);
  });

  testWidgets(
      'reports a page served from the wrong origin rather than showing nothing',
      (
    tester,
  ) async {
    final pending = await openSheet(
      tester,
      configuration(
          origin: 'https://elsewhere.example.com',
          fallBackToHostedCheckout: false),
    );

    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.notPaid);
    expect(result.code, CheckoutResultCode.checkoutUnavailable);
    expect(result.message, contains('registered origin'));
  });

  testWidgets('reports a closed sheet as cancelled', (tester) async {
    final pending = await openSheet(tester, configuration());

    await tester.tap(find.byTooltip(const PaymentSheetStrings().close));
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.cancelled);
    expect(result.message, closedByPayerMessage);
  });

  testWidgets('settles when the wallet comes back through the return link', (
    tester,
  ) async {
    declareHostAppSchemes(const <String>['myapp']);

    final pending = await openSheet(tester, configuration());
    final wallet = walletSurface();

    final decision = await wallet.navigation!.onNavigationRequest!(
      NavigationRequest(
        url: returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
        isMainFrame: true,
      ),
    );

    expect(decision, NavigationDecision.prevent);
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.paid);
    expect(result.invoiceId, '90210');
  });

  testWidgets('lets the wallet page itself load', (tester) async {
    await openSheet(tester, configuration());

    final decision = await walletSurface().navigation!.onNavigationRequest!(
      const NavigationRequest(url: testFieldsPageUrl, isMainFrame: true),
    );

    expect(decision, NavigationDecision.navigate);
  });

  /*
   * The wallet row's page is one the sheet takes a return link from, so it may hold only
   * the shop's own page and PayLink's, where a "Mobile App" integration's return link
   * forwards the payer from. Frames inside it are the wallet's own and load anything.
   */
  group('the wallet page', () {
    testWidgets('may not go to another website', (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface()..finishLoading();

      expect(
        await wallet.navigate('https://elsewhere.example/pay'),
        NavigationDecision.prevent,
      );
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsOneWidget,
          reason: 'its own page is still up');
    });

    for (final page in <String>[
      'data:text/html,<p>paid</p>',
      'blob:https://elsewhere.example/0b7c',
      'about:srcdoc',
      'file:///sdcard/page.html',
    ]) {
      testWidgets('may not be replaced by ${page.split(':').first}: page',
          (tester) async {
        await openSheet(tester, configuration());

        final wallet = walletSurface()..finishLoading();

        expect(await wallet.navigate(page), NavigationDecision.prevent);
      });
    }

    testWidgets("may go to PayLink's page that forwards to the app",
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface()..finishLoading();

      expect(
        await wallet.navigate(
          'https://pay.getpayin.com/integration/app-return?success=1&invoice_id=90210',
        ),
        NavigationDecision.navigate,
      );
    });

    testWidgets('still loads anything inside a frame', (tester) async {
      await openSheet(tester, configuration());

      expect(
        await walletSurface().navigate(
          'https://pay.google.com/gp/p/ui/pay',
          isMainFrame: false,
        ),
        NavigationDecision.navigate,
      );
    });

    testWidgets('sent elsewhere before it has loaded is taken away',
        (tester) async {
      await openSheet(tester, configuration());

      expect(
        await walletSurface().navigate('https://elsewhere.example/'),
        NavigationDecision.prevent,
      );
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing,
          reason: 'a page that never loads leaves an empty row');
    });
  });

  /*
   * The challenge is framed by the SDK inside the box and has to stay framed that way, so
   * the sheet gives it the screen rather than drawing its own chrome over it.
   */
  testWidgets('gives the issuer challenge the whole sheet', (tester) async {
    await openSheet(tester, configuration());

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);

    postToCard(<String, Object?>{
      'type': 'authenticating',
      'stage': 'challenge',
    });
    await pumpFrames(tester);

    expect(find.text(const PaymentSheetStrings().addNewCard), findsNothing);
    expect(find.text(r'Pay $97.42'), findsNothing);

    final box = tester.getSize(find.byType(CardBox));
    final sheet = tester.getSize(find.byType(GetPayInPaymentSheet));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(
      box.width,
      sheet.width,
      reason: 'the issuer formats its page for a window, and every point taken '
          'off the width is taken off the page',
    );
    expect(
      box.height,
      greaterThan(screen.height * 0.8),
      reason: 'a challenge drawn in a short box scrolls the field out of it',
    );
  });

  testWidgets('keeps the whole challenge above the keyboard on a notched phone',
      (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3)
      ..viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await openSheet(tester, configuration());
    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    postToCard(<String, Object?>{
      'type': 'authenticating',
      'stage': 'challenge',
    });
    await pumpFrames(tester);

    tester.view
      ..viewInsets = const FakeViewPadding(bottom: 336 * 3)
      ..padding = const FakeViewPadding(top: 47 * 3);
    await pumpFrames(tester);

    final box = tester.getRect(find.byType(CardBox));
    final sheet = tester.getRect(find.byType(GetPayInPaymentSheet));

    expect(
      box.bottom,
      lessThanOrEqualTo(844 - 336),
      reason: 'the bottom of the issuer page holds its code field and button',
    );
    expect(
      sheet.top,
      greaterThanOrEqualTo(47),
      reason: 'the sheet route takes the top inset away, so the sheet has to '
          'keep clear of the status bar itself',
    );
  });

  testWidgets('keeps a tall sheet below the status bar with the keyboard down',
      (tester) async {
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3)
      ..viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await openSheet(tester, configuration());
    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    postToCard(<String, Object?>{
      'type': 'authenticating',
      'stage': 'challenge',
    });
    await pumpFrames(tester);

    expect(
      tester.getRect(find.byType(GetPayInPaymentSheet)).top,
      greaterThanOrEqualTo(47),
      reason:
          'the home indicator inset sits under the sheet, inside its height',
    );
  });

  testWidgets('offers no wallet when none belongs on this phone',
      (tester) async {
    await openSheet(
      tester,
      configuration(wallets: const <PaymentWallet>[PaymentWallet.applePay]),
    );

    expect(find.text(const PaymentSheetStrings().orPayUsing), findsNothing);
    expect(find.text(const PaymentSheetStrings().newCard), findsOneWidget);
  });

  testWidgets('will not charge a saved card that has expired', (tester) async {
    await openSheet(
      tester,
      configuration(
        savedCards: const <SavedCard>[
          SavedCard(
              id: 'pm_1', last4: '7492', expiryMonth: 1, expiryYear: 2020),
          SavedCard(id: 'pm_2', last4: '8216'),
        ],
        chargeSavedCard: (card) async => const CheckoutResult(
          status: CheckoutStatus.paid,
        ),
      ),
    );

    // The expired one is not what the sheet opened on.
    expect(find.text('•••• 8216'), findsOneWidget);

    await tester.tap(find.text(const PaymentSheetStrings().viewMore));
    await pumpFrames(tester);

    expect(find.text(const PaymentSheetStrings().expired), findsOneWidget);

    await tester.tap(find.text('•••• 7492'));
    await pumpFrames(tester);

    // Tapping it did nothing: the list is still up.
    expect(find.text(const PaymentSheetStrings().selectCard), findsOneWidget);
  });

  /*
   * The sheet is the last thing a payer sees of their own payment. Closing the instant the
   * gateway answers reads as the sheet giving up rather than as it finishing, so it says so
   * first -- and still settles on the same result it would have settled on.
   */
  group('a payment that went through', () {
    testWidgets('is announced before the sheet closes', (tester) async {
      final pending = await openSheet(
        tester,
        configuration(successPause: const Duration(milliseconds: 1200)),
      );

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await tester.pump();

      expect(
        find.text(const PaymentSheetStrings().paymentComplete),
        findsOneWidget,
      );
      expect(find.text(r'$97.42'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });

    testWidgets('closes straight away when nothing is to be said',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(
        find.text(const PaymentSheetStrings().paymentComplete),
        findsNothing,
      );
      expect((await pending).status, CheckoutStatus.paid);
    });

    testWidgets('says nothing of the kind about a decline', (tester) async {
      await openSheet(
        tester,
        configuration(successPause: const Duration(milliseconds: 1200)),
      );

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      answerTheCharge(<String, Object?>{
        'success': false,
        'message': 'Your card was declined.',
      });
      await pumpFrames(tester);

      expect(
        find.text(const PaymentSheetStrings().paymentComplete),
        findsNothing,
      );
      expect(find.text('Your card was declined.'), findsOneWidget);
    });
  });

  /*
   * The address the card is billed to. The gateway's token carries none, so without one the
   * charge is matched against the company's placeholder address — and the gateway drops a
   * block that does not name the cardholder, which is why the box grows a name row with it.
   */
  group('the billing address', () {
    Future<void> fillIn(WidgetTester tester, String label, String value) async {
      await tester.enterText(find.widgetWithText(TextField, label), value);
      await pumpFrames(tester);
    }

    /// Scrolls the pay button into view and taps it, the way a payer has to.
    ///
    /// A card screen collecting an address is taller than the sheet, so the button really
    /// is below the fold until the payer scrolls to it.
    Future<void> tapPay(WidgetTester tester) async {
      await tester.ensureVisible(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
    }

    /// Opens the card screen of a sheet that collects an address, fields mounted.
    ///
    /// The page has to report that it loaded before the box is told what to render, and
    /// the name row is part of what it is told.
    Future<void> openCardScreen(WidgetTester tester) async {
      await openSheet(tester, configuration(collectBillingAddress: true));
      cardBox().finishLoading();
      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
    }

    testWidgets('is asked for under the card', (tester) async {
      await openCardScreen(tester);

      expect(
        find.text(const PaymentSheetStrings().billingAddress),
        findsOneWidget,
      );
      expect(
          find.text(const PaymentSheetStrings().addressLine), findsOneWidget);
      expect(find.text(const PaymentSheetStrings().city), findsOneWidget);
      expect(find.text(const PaymentSheetStrings().postalCode), findsOneWidget);
    });

    testWidgets('is not asked for by a sheet that does not collect it',
        (tester) async {
      await openSheet(tester, configuration());
      cardBox().finishLoading();
      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);

      expect(
        find.text(const PaymentSheetStrings().billingAddress),
        findsNothing,
      );
      expect(cardBox().scripts.first, contains('"collectName":false'));
    });

    testWidgets('has the box ask for the name the gateway cannot do without',
        (tester) async {
      await openCardScreen(tester);

      expect(cardBox().scripts.first, contains('"collectName":true'));
      expect(
        cardBox().scripts.first,
        contains('"nameLabel":"${const PaymentSheetStrings().nameOnCard}"'),
      );
    });

    testWidgets('holds the charge until there is an address to bill it to',
        (tester) async {
      await openCardScreen(tester);

      await tapPay(tester);

      expect(
        cardBox().scripts.where((script) => script.contains('.pay(')),
        isEmpty,
        reason: 'a card with no billing address is not chargeable yet',
      );

      postToCard(<String, Object?>{
        'type': 'change',
        'field': 'name',
        'empty': false,
        'value': 'Ada Lovelace',
      });
      await pumpFrames(tester);
      await fillIn(
          tester, const PaymentSheetStrings().addressLine, '12 Noyes Street');

      await tapPay(tester);

      expect(cardBox().scripts.last, contains('.pay('));
    });

    testWidgets('travels with the charge, under the gateway own names',
        (tester) async {
      await openCardScreen(tester);

      postToCard(<String, Object?>{
        'type': 'change',
        'field': 'name',
        'empty': false,
        'value': 'Ada Lovelace',
      });
      await pumpFrames(tester);

      await fillIn(
          tester, const PaymentSheetStrings().addressLine, '12 Noyes Street');
      await fillIn(tester, const PaymentSheetStrings().city, 'Cairo');
      await fillIn(tester, const PaymentSheetStrings().postalCode, '11511');

      await tapPay(tester);

      final charge = cardBox().scripts.last;

      expect(charge, contains('"firstName":"Ada"'));
      expect(charge, contains('"lastName":"Lovelace"'));
      expect(charge, contains('"country":"EG"'));
      expect(charge, contains('"address":"12 Noyes Street"'));
      expect(charge, contains('"city":"Cairo"'));
      expect(charge, contains('"postalCode":"11511"'));
    });
  });

  /*
   * A sheet that gives up mid-payment and hands the payer to the hosted checkout is doing
   * the right thing, but it used to do it silently: the integrator saw a browser open and
   * had nothing to go on. The reason is the one thing they need to fix it.
   */
  group('handing over to the hosted checkout', () {
    testWidgets('says why before it does', (tester) async {
      final reasons = <FieldsError>[];

      // The hosted checkout it hands to is not what is under test, and whether it opens
      // depends on a session guard other tests share.
      (await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      postToCard(<String, Object?>{
        'type': 'error',
        'code': 'origin_not_allowed',
        'message':
            'The card fields page is not served from the registered origin.',
      });
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(reasons.single.failure, FieldsFailure.originNotAllowed);
      expect(
        reasons.single.message,
        'The card fields page is not served from the registered origin.',
        reason:
            'an unmapped code is useless without the words that came with it',
      );
    });

    testWidgets('hands over with the country list open over the sheet',
        (tester) async {
      final reasons = <FieldsError>[];

      (await openSheet(
        tester,
        configuration(collectBillingAddress: true, onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);

      final countries = find.byType(DropdownButton<String>).first;

      await tester.ensureVisible(countries);
      await pumpFrames(tester);
      await tester.tap(countries);
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'error', 'code': 'session_invalid'});
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        reasons.single.failure,
        FieldsFailure.sessionInvalid,
        reason:
            'the list is a route too, and only the sheet is closed with this',
      );
    });

    testWidgets('says nothing for a decline the payer can retry',
        (tester) async {
      final reasons = <FieldsError>[];

      (await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      postToCard(<String, Object?>{
        'type': 'error',
        'code': 'card_invalid',
        'message': 'Please check the card details and try again.',
      });
      await pumpFrames(tester);

      expect(reasons, isEmpty);
    });
  });

  /*
   * A charge that started and then lost its answer is the one outcome nobody knows. The
   * sheet used to report every one of them as a payment that did not happen -- the payer
   * sent to the hosted checkout to pay again, or told `checkoutUnavailable`, which the docs
   * define as nothing having been charged. Both invite a second charge for a card that may
   * already have been charged once.
   */
  group('a charge whose answer never came', () {
    Future<Future<CheckoutResult>> startCharging(
      WidgetTester tester, {
      bool fallBack = true,
    }) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: fallBack),
        withProvider: true,
      );

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'charging'});
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('is not reported as a checkout that never ran', (tester) async {
      final pending = await startCharging(tester, fallBack: false);

      failTheCharge(<String, Object?>{
        'code': 'a_code_this_package_does_not_know',
        'message': 'The answer was lost.',
      });
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('never sends the payer to pay a second time', (tester) async {
      final pending = await startCharging(tester);

      failTheCharge(<String, Object?>{
        'code': 'session_invalid',
        'message': 'The answer was lost.',
      });
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
      expect(
        launcher.launches,
        isEmpty,
        reason:
            'the hosted checkout would charge a card that may already be charged',
      );
    });

    testWidgets('cannot be dismissed out from under the payer', (tester) async {
      final pending = await startCharging(tester, fallBack: false);

      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(
        (await pending).status,
        CheckoutStatus.paid,
        reason: 'the charge was with the gateway when the barrier was tapped',
      );
    });

    testWidgets('still closes on a tap outside before anything is charged',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    testWidgets('holds the one-checkout-at-a-time guard while it is open',
        (tester) async {
      expect(GetPayInCheckout.busy, isFalse);

      final pending = await openSheet(tester, configuration());

      expect(
        GetPayInCheckout.busy,
        isTrue,
        reason: 'taking-payments.md tells integrators to gate Pay on this',
      );

      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);
      await pending;

      expect(GetPayInCheckout.busy, isFalse);
    });

    testWidgets('does not invite a second card when your server threw',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(
          savedCards: <SavedCard>[
            const SavedCard(id: 'pm_1', last4: '4242'),
          ],
          chargeSavedCard: (_) async => throw StateError('the network went'),
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(
        result.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'a timeout can follow a card your server already charged',
      );
      expect(
        find.text(const PaymentSheetStrings().cardDeclined),
        findsNothing,
      );
    });

    testWidgets('lets the payer try the wallet again after a decline',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      await openSheet(tester, configuration());

      final first = walletSurface();

      await first.navigation!.onNavigationRequest!(
        NavigationRequest(
          url: returnLink('success=0&invoice_id=90210&message=Declined'),
          isMainFrame: true,
        ),
      );
      await pumpFrames(tester);

      expect(
        walletSurface(),
        isNot(same(first)),
        reason: 'the old surface has latched and would swallow the next answer',
      );
    });

    testWidgets('still falls back when the charge had not started',
        (tester) async {
      await openSheet(tester, configuration(), withProvider: true);

      postToCard(<String, Object?>{'type': 'error', 'code': 'session_invalid'});
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(launcher.launches.single.$1, testCheckoutUrl);
    });
  });

  /*
   * A payer must always be able to leave, even mid-charge, because a charge can hang. But a
   * charge that is running when they leave may still go through, so every way out of one
   * says the payment could not be confirmed: never cancelled, which reads as nothing having
   * happened.
   */
  group('a way out of a running charge', () {
    const strings = PaymentSheetStrings();

    /// Opens the card screen of a complete card and taps Pay on it.
    Future<Future<CheckoutResult>> payByCard(WidgetTester tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('closing during a saved-card charge reports it unconfirmed',
        (tester) async {
      final pending = await openSheet(
        tester,
        slowSavedCard(Completer<CheckoutResult>()),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets(
        'the card screen offers a close instead of back while it charges',
        (tester) async {
      final pending = await payByCard(tester);

      expect(find.byTooltip(strings.back), findsNothing);

      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('the bank check can be closed, and that reports it unconfirmed',
        (tester) async {
      final pending = await payByCard(tester);

      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('Android Back while the issuer is asked leaves the sheet open',
        (tester) async {
      final pending = await payByCard(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      postToCard(<String, Object?>{'type': 'authenticating'});
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(
        settled,
        isNull,
        reason: 'the SDK goes on to charge after the issuer answers',
      );
    });

    testWidgets('an unconfirmed charge is told in the sheet own words',
        (tester) async {
      final pending = await payByCard(tester);

      postToCard(<String, Object?>{'type': 'charging'});
      await pumpFrames(tester);
      failTheCharge(<String, Object?>{
        'code': 'a_code_this_package_does_not_know',
        'message': 'Please try another card.',
      });
      await pumpFrames(tester);

      expect(
        (await pending).message,
        strings.outcomeUnknown,
        reason: 'the page text could invite a second payment',
      );
    });

    testWidgets('a charge that answers after the payer left changes nothing',
        (tester) async {
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(
        tester,
        slowSavedCard(
          answer,
          successPause: const Duration(milliseconds: 1200),
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      answer.complete(const CheckoutResult(
        status: CheckoutStatus.paid,
        invoiceId: '90210',
        invoiceStatus: 'PAID',
      ));
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });
  });

  /*
   * PayLink answers a paid invoice with `already_paid` as soon as the fields open. The
   * payer may well have paid it a minute ago in another tab, so nothing here may read as
   * nothing having happened: an app told that creates a second payment for the order.
   */
  group('an invoice PayLink says is already paid', () {
    for (final fallBack in <bool>[true, false]) {
      testWidgets(
          'is reported unconfirmed with the fallback ${fallBack ? 'on' : 'off'}',
          (tester) async {
        final pending = await openSheet(
          tester,
          configuration(fallBackToHostedCheckout: fallBack),
          withProvider: true,
        );

        CheckoutResult? settled;

        unawaited(pending.then((result) => settled = result));

        postToCard(<String, Object?>{
          'type': 'error',
          'code': 'already_paid',
          'message': 'This payment has already been completed.',
        });
        await pumpFrames(tester);
        await pumpFrames(tester);

        expect(launcher.launches, isEmpty);
        expect(settled?.code, CheckoutResultCode.outcomeUnknown);
      });
    }
  });

  /*
   * A saved card's charge runs on your server, and the issuer can answer it with a challenge
   * the payer has to see. Your server hands back its URL, and `chargeSavedCard` opens it as
   * a checkout of its own while the sheet still holds the one-checkout guard.
   */
  testWidgets('opens a saved card bank check as its own checkout',
      (tester) async {
    final pending = await openSheet(
      tester,
      configuration(
        savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
        chargeSavedCard: (_) => GetPayInCheckout.open(
          testCheckoutUrl,
          const OpenCheckoutOptions(
            returnUrl: testReturnUrl,
            presentation: CheckoutPresentation.inApp,
            expectedInvoiceId: '90210',
          ),
        ),
      ),
      withProvider: true,
    );

    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);
    await webView.navigate(
      returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
    );
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.paid);
    expect(GetPayInCheckout.busy, isFalse);
  });

  /*
   * One sheet takes one payment at a time. With a saved card charging on your server, every
   * other way to pay on the same sheet is one tap from a second charge for the same order.
   */
  group('a second payment while one runs', () {
    const strings = PaymentSheetStrings();

    testWidgets('a saved-card charge takes the wallet away until it answers',
        (tester) async {
      final answer = Completer<CheckoutResult>();

      await openSheet(tester, slowSavedCard(answer));

      expect(find.byType(WalletSurface), findsOneWidget);

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing);

      answer.complete(const CheckoutResult(
        status: CheckoutStatus.notPaid,
        message: 'Declined',
      ));
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsOneWidget,
        reason: 'a decline is an answer, and the payer may pay another way',
      );
    });

    testWidgets('a saved-card charge keeps the other methods shut',
        (tester) async {
      await openSheet(tester, slowSavedCard(Completer<CheckoutResult>()));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.text(strings.newCard), warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text(strings.addNewCard), findsNothing);
      expect(find.text(strings.viewMore), findsNothing);
    });
  });

  /*
   * Once the sheet has its answer, nothing after it may change what the app is told: not
   * the payer leaving the success screen, not the app's own navigation, not a late message
   * from the page, and not an answer that lands while the sheet is still closing.
   */
  group('the sheet once it knows how it ends', () {
    const strings = PaymentSheetStrings();

    /// Pays a complete card and answers it paid, leaving the success screen up.
    Future<Future<CheckoutResult>> payAndSucceed(WidgetTester tester) async {
      final pending = await openSheet(
        tester,
        configuration(successPause: const Duration(milliseconds: 1200)),
        withProvider: true,
      );

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await tester.pump();

      return pending;
    }

    testWidgets('leaving the success screen early still reports it paid',
        (tester) async {
      final pending = await payAndSucceed(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 2));
      await pumpFrames(tester);

      expect(settled?.status, CheckoutStatus.paid);
    });

    testWidgets('a failure after the payment went through changes nothing',
        (tester) async {
      final pending = await payAndSucceed(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      postToCard(<String, Object?>{'type': 'error', 'code': 'session_invalid'});
      await tester.pump(const Duration(seconds: 2));
      await pumpFrames(tester);

      expect(launcher.launches, isEmpty);
      expect(settled?.status, CheckoutStatus.paid);
    });

    /*
     * A sheet opened from a nested navigator — a shell route, a tab — goes with that
     * navigator when the app leaves it, and so does a whole MaterialApp rebuilt on sign-out.
     * Nothing pops the route then, so nothing answers it: without this, the sheet's own
     * future stays pending and the one-checkout guard holds for the rest of the process.
     *
     * The app is replaced with a tree of another kind on purpose. A second MaterialApp
     * would update the first one's element, navigator and all, and the route would survive
     * the thing the test is about.
     */
    testWidgets('answers when the navigator it was in is taken away',
        (tester) async {
      final pending = await openSheet(
        tester,
        slowSavedCard(Completer<CheckoutResult>()),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('signed out'),
        ),
      );
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'a charge was out, so what became of it is not known here',
      );
      expect(
        GetPayInCheckout.busy,
        isFalse,
        reason: 'a guard still held would refuse every later payment',
      );
    });

    testWidgets('the app closing the sheet mid-charge reports it unconfirmed',
        (tester) async {
      final pending = await openSheet(
        tester,
        slowSavedCard(Completer<CheckoutResult>()),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'Back is refused, but a pop made in code cannot be',
      );
    });

    testWidgets('leaves the app its screens when they were reset under it',
        (tester) async {
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(tester, slowSavedCard(answer));

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const Text('signed out')),
              (route) => route.isFirst,
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      answer.completeError(StateError('the session expired'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('signed out'), findsOneWidget);
      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('an answer while the sheet is closing leaves the app alone',
        (tester) async {
      final answer = Completer<CheckoutResult>();

      await openSheet(tester, slowSavedCard(answer));
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await tester.pump();

      answer.complete(const CheckoutResult(
        status: CheckoutStatus.paid,
        invoiceId: '90210',
        invoiceStatus: 'PAID',
      ));
      await tester.pump();
      await pumpFrames(tester);

      expect(
        find.text('checkout'),
        findsOneWidget,
        reason: 'a second pop would take the screen under the sheet with it',
      );
    });

    testWidgets('the wallet marking a charge after the sheet left is ignored',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();

      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);
      wallet.changeUrl('$testFieldsPageUrl#paylink-charging');
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    /*
     * A saved card's challenge is a checkout of its own, and a payer can close it after
     * answering the issuer, with the charge already on its way. The sheet cannot tell that
     * from closing before answering.
     */
    testWidgets(
        'a saved card whose challenge was closed reports it unconfirmed',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(
          savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
          chargeSavedCard: (_) async => cancelledResult(closedByPayerMessage),
        ),
      );

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });
  });

  /*
   * A wallet payment can get the issuer's 3-D Secure check, drawn by the SDK over the whole
   * wallet page. In a button-high row the payer could not answer it, so the sheet gives the
   * wallet its whole height while the check is up, on the same page: a new one would lose it.
   */
  group('a bank check on the wallet', () {
    const strings = PaymentSheetStrings();

    String challenge() => '$testFieldsPageUrl#paylink-challenge';
    String ended() => '$testFieldsPageUrl#paylink-challenge-ended';
    String charging() => '$testFieldsPageUrl#paylink-charging';
    double walletHeight(WidgetTester tester) =>
        tester.getSize(find.byType(WalletSurface)).height;

    testWidgets('gives the wallet the whole sheet, on the same page',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();
      final row = walletHeight(tester);

      wallet.changeUrl(challenge());
      await pumpFrames(tester);

      expect(walletSurface(), same(wallet),
          reason: 'a new page would lose the check');
      expect(walletHeight(tester), greaterThan(row * 4));
      expect(find.text(strings.newCard), findsNothing);
      expect(find.byTooltip(strings.close), findsOneWidget);
    });

    testWidgets('holds the sheet while it is up', (tester) async {
      final pending = await openSheet(tester, configuration());

      walletSurface().changeUrl(challenge());
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));
      await tester.pump();

      expect(settled, isNull, reason: 'Back does not close it');

      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('gives the row back when it ends with no charge',
        (tester) async {
      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();
      final row = walletHeight(tester);

      wallet.changeUrl(challenge());
      await pumpFrames(tester);
      wallet.changeUrl(ended());
      await pumpFrames(tester);

      expect(walletHeight(tester), row);
      expect(find.text(strings.newCard), findsOneWidget);

      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    /*
     * The mark can land in the frame in which another payment starts, from a button the
     * sheet is about to take away. That page is emptied as the button goes, before any
     * charge, so the mark is ignored: taken, it would bring the wallet back beside the
     * other payment, or lock the card screen.
     */
    testWidgets(
        'a check from a button that is leaving brings it back for nothing',
        (tester) async {
      await openSheet(tester, slowSavedCard(Completer<CheckoutResult>()));

      final wallet = walletSurface();

      await tester.tap(find.text(r'Pay $97.42'));
      wallet.changeUrl(challenge());
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing,
          reason: 'a saved card is being charged');
    });

    testWidgets('a check from a button the payer has left leaves the card free',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      wallet.changeUrl(challenge());
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(chargeCode(), isNotEmpty, reason: 'Pay still charges the card');
    });

    /// A touch on the wallet button, then the app behind the wallet's own sheet and back.
    Future<void> visitTheWallet(WidgetTester tester) async {
      await tester.tapAt(tester.getCenter(find.byType(WalletSurface)));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    testWidgets("stays held past the wallet's own 15 seconds", (tester) async {
      final pending = await openSheet(tester, configuration());
      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await visitTheWallet(tester);
      walletSurface().changeUrl(challenge());
      await pumpFrames(tester);
      await tester.pump(const Duration(seconds: 20));
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull);
      expect(find.text(strings.newCard), findsNothing,
          reason: 'the check is still up');

      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('hands over a card-box failure kept for after it',
        (tester) async {
      final reasons = <FieldsError>[];

      (await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      final wallet = walletSurface();

      wallet.changeUrl(challenge());
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'error', 'code': 'session_invalid'});
      await pumpFrames(tester);

      expect(reasons, isEmpty, reason: 'the issuer may yet pass the check');

      wallet.changeUrl(ended());
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(reasons.single.failure, FieldsFailure.sessionInvalid);
    });

    testWidgets('ends unconfirmed after it when a stray wallet charge came in',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final old = walletSurface();

      await old.navigate(
        returnLink('success=0&invoice_id=90210&message=Declined'),
      );
      await pumpFrames(tester);

      final fresh = walletSurface();

      fresh.changeUrl(challenge());
      await pumpFrames(tester);
      old.changeUrl(charging());
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'the check is still up');

      fresh.changeUrl(ended());
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('settles on the wallet answer once the charge is out',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(challenge());
      await pumpFrames(tester);
      wallet.changeUrl(charging());
      await pumpFrames(tester);

      expect(walletSurface(), same(wallet));

      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });
  });

  /*
   * A wallet charge runs on the page after the wallet's own sheet has closed, for the few
   * seconds the gateway takes to answer. The surface has no channel, so the page marks its
   * own address when the charge is out, and the sheet holds still until the answer.
   */
  group('a wallet charge', () {
    const strings = PaymentSheetStrings();

    /// The wallet page's address once it has said its charge is out.
    String charging() => '$testFieldsPageUrl#paylink-charging';

    testWidgets('holds the sheet open from the moment it is out',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      walletSurface().changeUrl(charging());
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect(settled, isNull);
    });

    testWidgets('counts the mark the same when it arrives as a navigation',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      expect(
        await walletSurface().navigate(charging()),
        NavigationDecision.navigate,
      );
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'iOS reports a fragment as a navigation');
    });

    testWidgets('keeps the wallet and shuts everything else while it runs',
        (tester) async {
      await openSheet(
        tester,
        slowSavedCard(Completer<CheckoutResult>()),
      );

      walletSurface().changeUrl(charging());
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsOneWidget,
        reason: 'the surface is what the answer arrives on',
      );

      await tester.tap(find.text(strings.newCard), warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text(strings.addNewCard), findsNothing);
    });

    testWidgets('closing while it runs reports it unconfirmed', (tester) async {
      final pending = await openSheet(tester, configuration());

      walletSurface().changeUrl(charging());
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('an answer after the payer left changes nothing',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);
      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect((await pending).code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('an answer while the sheet is closing changes nothing',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await tester.pump();
      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        (await pending).code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'the button is still on screen while the sheet slides away',
      );
    });

    testWidgets('a decline naming another invoice does not end it',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);

      expect(
        await wallet.navigate(returnLink('success=0&invoice_id=11111')),
        NavigationDecision.prevent,
      );
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect(
        (await pending).code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'the real wallet charge is still out',
      );
    });

    testWidgets('still settles on the answer after the mark', (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });

    testWidgets('lets the payer close normally after a declined wallet',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());

      walletSurface().changeUrl(charging());
      await pumpFrames(tester);
      await walletSurface().navigate(
        returnLink('success=0&invoice_id=90210&message=Declined'),
      );
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });
  });

  /*
   * The wallet's own sheet is another app's screen over this one, and the page only says its
   * charge is out a few seconds after that sheet has closed. The page cannot see the wallet
   * open or close; the app can, because the wallet puts it in the background. From then
   * until a charge or an answer, leaving the sheet could lose a payment about to go through.
   */
  group('a wallet the payer has opened', () {
    const strings = PaymentSheetStrings();

    /// The app going to the background and coming back, for whatever reason.
    Future<void> leaveTheApp(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    /// A touch on the wallet button, then the app behind the wallet's own sheet and back.
    Future<void> visitTheWallet(WidgetTester tester) async {
      await tester.tapAt(tester.getCenter(find.byType(WalletSurface)));
      await tester.pump();
      await leaveTheApp(tester);
    }

    testWidgets('holds the sheet before its charge is out', (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await visitTheWallet(tester);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect(settled, isNull);
    });

    testWidgets('keeps the wallet and shuts everything else while it is open',
        (tester) async {
      await openSheet(tester, slowSavedCard(Completer<CheckoutResult>()));

      await visitTheWallet(tester);
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsOneWidget,
        reason: 'the surface is what the charge runs on',
      );

      await tester.tap(find.text(strings.newCard), warnIfMissed: false);
      await pumpFrames(tester);

      expect(find.text(strings.addNewCard), findsNothing);
    });

    testWidgets('lets go when no charge comes after the payer is back',
        (tester) async {
      await openSheet(tester, configuration());

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(find.text(strings.addNewCard), findsOneWidget);
    });

    testWidgets('closing after a wallet that never answered is unconfirmed',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect(
        (await pending).code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'a wallet slower than the wait can still charge',
      );
    });

    testWidgets('the wait running out does not free a charge that is out',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 4));
      walletSurface().changeUrl('$testFieldsPageUrl#paylink-charging');
      await tester.pump(const Duration(seconds: 15));
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull);
    });

    testWidgets('a charge marked after the wait ran out holds it again',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 15));
      walletSurface().changeUrl('$testFieldsPageUrl#paylink-charging');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull);
    });

    testWidgets('leaving the app without touching the wallet holds nothing',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await leaveTheApp(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect(
        (await pending).status,
        CheckoutStatus.cancelled,
        reason: 'a payer may pull down a notification or take a call',
      );
    });

    testWidgets('a touch on the wallet long before leaving holds nothing',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tapAt(tester.getCenter(find.byType(WalletSurface)));
      await tester.pump(const Duration(seconds: 11));
      await leaveTheApp(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    /*
     * A wallet button that leaves the screen keeps its page, and the page goes on with a
     * wallet charge it was still preparing. After the wait has run out, that is a charge the
     * sheet no longer holds still for, beside whatever the payer pays with next.
     */
    testWidgets('empties a wallet button that leaves the screen',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(wallet.loaded.last, Uri.parse('about:blank'));
    });

    testWidgets('a wallet button that left the screen cannot settle the sheet',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(
        tester,
        slowSavedCard(Completer<CheckoutResult>()),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 15));
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      wallet.changeUrl('$testFieldsPageUrl#paylink-charging');
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsNothing,
        reason: 'a late mark from it must not bring a wallet back',
      );

      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect(
        settled,
        isNull,
        reason:
            'the saved card is still charging, and its answer is the one due',
      );
    });

    testWidgets('a wallet button that left lets only the blank page load',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(
        await wallet.navigate('about:blank'),
        NavigationDecision.navigate,
        reason: 'iOS asks before loading even the blank page',
      );
      expect(
        await wallet.navigate(testFieldsPageUrl),
        NavigationDecision.prevent,
      );
    });

    testWidgets('a wallet button that leaves before its page loads never loads',
        (tester) async {
      final settings = Completer<void>();

      walletSettingsApplier = (controller, applied) => settings.future;
      addTearDown(() => walletSettingsApplier = applyWalletSettings);

      await openSheet(tester, configuration());

      final wallet = webView.controllers.last;

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      settings.complete();
      await pumpFrames(tester);

      expect(
        wallet.loaded,
        <Uri>[Uri.parse('about:blank')],
        reason: 'Android never asks before an app loads its own page',
      );
    });

    testWidgets('leaving during a saved-card charge brings no wallet back',
        (tester) async {
      await openSheet(tester, slowSavedCard(Completer<CheckoutResult>()));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      await leaveTheApp(tester);
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsNothing,
        reason: 'a wallet during a saved card is a second way to pay',
      );
    });

    testWidgets('waits again from the payer coming back a second time',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 10));
      await visitTheWallet(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull);
    });

    testWidgets('a declined wallet closes as cancelled again', (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());

      await visitTheWallet(tester);
      await walletSurface().navigate(
        returnLink('success=0&invoice_id=90210&message=Declined'),
      );
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    testWidgets('leaving the app holds nothing when no wallet is offered',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(wallets: const <PaymentWallet>[PaymentWallet.applePay]),
      );

      await leaveTheApp(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.cancelled);
    });

    testWidgets('leaving the app from the card form holds nothing',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await leaveTheApp(tester);
      await tester.tap(find.byTooltip(strings.back));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.close));
      await pumpFrames(tester);

      expect(
        (await pending).status,
        CheckoutStatus.cancelled,
        reason: 'a payer may switch apps to copy their card number',
      );
    });
  });

  /*
   * A wallet charge can go out the moment the sheet stops holding for it: the payer pays a
   * saved card in the same instant, or has already moved on to the card form. Its answer
   * then has nowhere to arrive, so whatever the sheet reports next could hide a second
   * payment, and it is reported unconfirmed instead.
   */
  group('a wallet charge nobody was holding for', () {
    const strings = PaymentSheetStrings();

    String charging() => '$testFieldsPageUrl#paylink-charging';

    const paid = CheckoutResult(
      status: CheckoutStatus.paid,
      invoiceId: '90210',
      invoiceStatus: 'PAID',
    );

    testWidgets('marked as a saved card starts makes its answer unconfirmed',
        (tester) async {
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(tester, slowSavedCard(answer));

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(r'Pay $97.42'));
      wallet.changeUrl(charging());
      await pumpFrames(tester);
      answer.complete(paid);
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets(
        'marked after its button left makes the next answer unconfirmed',
        (tester) async {
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(tester, slowSavedCard(answer));

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(wallet.loaded.last, Uri.parse('about:blank'));

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      answer.complete(paid);
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('closes the sheet unconfirmed on a decline that follows it',
        (tester) async {
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(tester, slowSavedCard(answer));

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      wallet.changeUrl(charging());
      await pumpFrames(tester);
      answer.complete(const CheckoutResult(
        status: CheckoutStatus.notPaid,
        message: 'Declined',
      ));
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'another try now could be a second payment',
      );
    });

    testWidgets('marked while the payer is on the card form ends the sheet',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(wallet.loaded.last, Uri.parse('about:blank'));

      wallet.changeUrl(charging());
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('counts a late mark the same when it arrives as a navigation',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(wallet.loaded.last, Uri.parse('about:blank'));

      await wallet.navigate(charging());
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'iOS reports a fragment as a navigation',
      );
    });

    testWidgets('marked by a button that left counts once a new one is shown',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final old = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.back));
      await pumpFrames(tester);

      expect(walletSurface(), isNot(same(old)));
      expect(old.loaded.last, Uri.parse('about:blank'));

      old.changeUrl(charging());
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason:
            'that charge answers on a page that is gone, not on the new one',
      );
    });

    testWidgets('marked while the payer is in the wallet ends the sheet after',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final old = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(strings.back));
      await pumpFrames(tester);
      await tester.tapAt(tester.getCenter(find.byType(WalletSurface)));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      old.changeUrl(charging());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(settled, isNull, reason: 'the payer is still in the new wallet');

      await tester.pump(const Duration(seconds: 15));
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'a sheet that frees itself here takes a second payment',
      );
    });

    testWidgets(
        'closes the sheet unconfirmed on a card failure that follows it',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      final wallet = walletSurface();

      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      wallet.changeUrl(charging());
      await pumpFrames(tester);
      failTheCharge(<String, Object?>{
        'code': 'authentication_abandoned',
        'message': 'Card verification was not completed.',
      });
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'another try now could be a second payment',
      );
    });
  });

  /*
   * A wallet charge answers on its own button, so from the page's mark until the answer the
   * payer stays where that button is. The row they tap was drawn before the mark arrived, so
   * the sheet checks again when the tap lands.
   */
  group('a wallet charge the sheet is holding for', () {
    const strings = PaymentSheetStrings();

    String charging() => '$testFieldsPageUrl#paylink-charging';

    testWidgets('keeps the payer off the card form', (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await tester.tap(find.text(strings.newCard));
      await pumpFrames(tester);

      expect(find.text(strings.addNewCard), findsNothing);

      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });

    testWidgets('keeps the payer off the saved cards', (tester) async {
      await openSheet(tester, slowSavedCard(Completer<CheckoutResult>()));

      walletSurface().changeUrl(charging());
      await tester.tap(find.text(strings.viewMore));
      await pumpFrames(tester);

      expect(find.text(strings.selectCard), findsNothing);
    });
  });

  /*
   * The card box loads behind the first screen, so it can fail while the wallet or a saved
   * card is charging. Handing the payer over then would open a second way to pay for the
   * same order, so the sheet waits for that payment's answer first.
   */
  group('a card form that fails while another payment is out', () {
    String charging() => '$testFieldsPageUrl#paylink-charging';

    void failTheCardForm() => postToCard(
          <String, Object?>{'type': 'error', 'code': 'session_invalid'},
        );

    testWidgets('waits for a wallet charge, and hands nothing over once paid',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final reasons = <FieldsError>[];
      final pending = await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      );
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      failTheCardForm();
      await pumpFrames(tester);

      expect(reasons, isEmpty);

      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
      expect(reasons, isEmpty);
    });

    testWidgets('hands over once the wallet is declined', (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final reasons = <FieldsError>[];

      (await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      failTheCardForm();
      await pumpFrames(tester);

      expect(reasons, isEmpty);

      await wallet.navigate(
        returnLink('success=0&invoice_id=90210&message=Declined'),
      );
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(reasons.single.failure, FieldsFailure.sessionInvalid);
    });

    testWidgets('takes the wallet answer over a card form told it is paid',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'error', 'code': 'already_paid'});
      await pumpFrames(tester);
      await wallet.navigate(
        returnLink('success=1&invoice_id=90210&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect(
        (await pending).status,
        CheckoutStatus.paid,
        reason: 'that wallet charge is what paid the invoice',
      );
    });

    testWidgets('ends unconfirmed on a paid card form once the wallet declines',
        (tester) async {
      declareHostAppSchemes(const <String>['myapp']);

      final pending = await openSheet(tester, configuration());
      final wallet = walletSurface();

      wallet.changeUrl(charging());
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'error', 'code': 'already_paid'});
      await pumpFrames(tester);
      await wallet.navigate(
        returnLink('success=0&invoice_id=90210&message=Declined'),
      );
      await pumpFrames(tester);

      expect(
        (await pending).code,
        CheckoutResultCode.outcomeUnknown,
        reason: 'something else paid the invoice, and nobody knows what',
      );
    });

    testWidgets("keeps a saved card's charge held until it is declined",
        (tester) async {
      final reasons = <FieldsError>[];
      final answer = Completer<CheckoutResult>();
      final pending = await openSheet(
        tester,
        configuration(
          savedCards: const <SavedCard>[SavedCard(id: 'pm_1', last4: '7492')],
          chargeSavedCard: (_) => answer.future,
          onHandover: reasons.add,
        ),
        withProvider: true,
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      failTheCardForm();
      postToCard(<String, Object?>{
        'type': 'error',
        'code': 'card_invalid',
        'message': 'Please check the card details and try again.',
      });
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'the saved card is still being charged');
      expect(reasons, isEmpty);

      answer.complete(
        const CheckoutResult(status: CheckoutStatus.notPaid, message: 'No'),
      );
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(reasons.single.failure, FieldsFailure.sessionInvalid);
    });

    for (final fallBack in <bool>[true, false]) {
      testWidgets(
          'ends unconfirmed once a wallet that never answered lets go, '
          'with the fallback ${fallBack ? 'on' : 'off'}', (tester) async {
        final reasons = <FieldsError>[];
        final pending = await openSheet(
          tester,
          configuration(
            fallBackToHostedCheckout: fallBack,
            onHandover: reasons.add,
          ),
          withProvider: true,
        );

        CheckoutResult? settled;

        unawaited(pending.then((result) => settled = result));

        await tester.tapAt(tester.getCenter(find.byType(WalletSurface)));
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        failTheCardForm();
        await tester.pump();
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await pumpFrames(tester);

        expect(settled, isNull);

        await tester.pump(const Duration(seconds: 15));
        await pumpFrames(tester);

        expect(
          reasons,
          isEmpty,
          reason: 'the wallet can still charge, so a second way to pay is not '
              'offered',
        );
        expect(settled?.code, CheckoutResultCode.outcomeUnknown);
      });
    }
  });

  /*
   * A charge that was refused, or a bank check that never got as far as the charge, is an
   * answer: nothing is in flight any more, and the payer is free to try again or to leave.
   */
  group('an attempt that ended without a payment', () {
    /// Opens the card screen of a complete card and taps Pay on it.
    Future<Future<CheckoutResult>> payByCard(WidgetTester tester) async {
      final pending = await openSheet(tester, configuration());

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('lets the payer try again after leaving the bank check',
        (tester) async {
      final pending = await payByCard(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });
      await pumpFrames(tester);
      failTheCharge(<String, Object?>{
        'code': 'authentication_abandoned',
        'message': 'Card verification was not completed.',
      });
      await pumpFrames(tester);

      expect(
        settled,
        isNull,
        reason: 'the SDK asks the bank before it charges: nothing was charged',
      );
      expect(find.text('Card verification was not completed.'), findsOneWidget);
      expect(find.text(r'Pay $97.42'), findsOneWidget);
    });

    testWidgets('closes as cancelled after a decline', (tester) async {
      final pending = await payByCard(tester);

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      postToCard(<String, Object?>{'type': 'charging'});
      await pumpFrames(tester);
      answerTheCharge(<String, Object?>{
        'success': false,
        'invoiceId': 90210,
        'message': 'Card declined',
      });
      await pumpFrames(tester);

      await tester.tapAt(const Offset(10, 10));
      await pumpFrames(tester);

      expect(
        settled?.status,
        CheckoutStatus.cancelled,
        reason: 'a decline leaves nothing in flight, so the sheet may close',
      );
    });
  });

  /*
   * The card box talks to one page, over a channel everything that page frames can post on,
   * and no platform names the sender of a message. So it answers one charge, the one it
   * asked for, and gives its top frame to the registered origin and nothing else.
   */
  group('a card page that cannot take the charge', () {
    testWidgets('hands over when it cannot be asked to pay', (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      cardBox().scriptFailure = StateError('the web view is gone');
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.checkoutUnavailable,
        reason: 'nothing reached the page, so nothing was charged',
      );
    });

    testWidgets('hands over when it cannot be started', (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      cardBox()
        ..scriptFailure = StateError('the web view is gone')
        ..finishLoading();
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.checkoutUnavailable);
    });

    testWidgets('asks for the consent tick again rather than handing over',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      failTheCharge(<String, Object?>{
        'code': 'consent_required',
        'message': 'Tick the box to keep this card.',
      });
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'the payer can fix this on the form');
      expect(find.text('Tick the box to keep this card.'), findsOneWidget);
    });

    testWidgets('hands over when it does not load', (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      cardBox().navigation?.onWebResourceError?.call(
            const WebResourceError(
              errorCode: -2,
              description: 'no connection',
              isForMainFrame: true,
            ),
          );
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.checkoutUnavailable);
    });

    testWidgets('hands over when its address serves some other page',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      cardBox()
        ..startAnswer = false
        ..finishLoading();
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.checkoutUnavailable,
        reason: 'an error page, or any page without the card script, '
            'is not the card page, whatever its status said',
      );
    });

    testWidgets('hands over when its page fails after the fields were up',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await completeTheCard(tester);
      cardBox().navigation?.onWebResourceError?.call(
            const WebResourceError(
              errorCode: 2,
              description: 'the web content process ended',
              isForMainFrame: true,
            ),
          );
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.checkoutUnavailable);
    });

    testWidgets('takes the wallet away on an iPhone error answer',
        (tester) async {
      await openSheet(tester, configuration());

      walletSurface().navigation?.onHttpError?.call(
            HttpResponseError(
              response: WebResourceResponse(uri: null, statusCode: 502),
            ),
          );
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsNothing,
        reason: 'iOS names no address on an HTTP error; before the page is up, '
            'it is the page',
      );
    });

    testWidgets('holds through a page failure while the issuer asks',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });
      await pumpFrames(tester);
      cardBox().navigation?.onWebResourceError?.call(
            const WebResourceError(
              errorCode: -2,
              description: 'no connection',
              isForMainFrame: true,
            ),
          );
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'the charge can still go through');

      await tester.tap(find.byTooltip(const PaymentSheetStrings().close));
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.outcomeUnknown);
    });

    testWidgets('keeps holding when its page loads again mid-charge',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await completeTheCard(tester);
      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'charging'});
      await pumpFrames(tester);
      cardBox().navigation?.onPageStarted?.call(testFieldsPageUrl);
      await pumpFrames(tester);
      await tester.binding.handlePopRoute();
      await pumpFrames(tester);

      expect(settled, isNull, reason: 'Back is refused while a charge is out');
    });

    testWidgets(
        'keeps the wallet row when its page fails after the charge mark',
        (tester) async {
      await openSheet(tester, configuration());

      final wallet = walletSurface();

      wallet.changeUrl('$testFieldsPageUrl#paylink-charging');
      await pumpFrames(tester);
      wallet.navigation?.onWebResourceError?.call(
        const WebResourceError(
          errorCode: -2,
          description: 'no connection',
          isForMainFrame: true,
        ),
      );
      await pumpFrames(tester);

      expect(
        find.byType(WalletSurface),
        findsOneWidget,
        reason: "the charge's answer arrives on that surface",
      );
    });

    testWidgets('takes the wallet away when its address answers an error',
        (tester) async {
      await openSheet(tester, configuration());

      walletSurface().navigation?.onHttpError?.call(
            HttpResponseError(
              request: WebResourceRequest(uri: Uri.parse(testFieldsPageUrl)),
              response: WebResourceResponse(
                uri: Uri.parse(testFieldsPageUrl),
                statusCode: 404,
              ),
            ),
          );
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing);
    });

    testWidgets('takes the wallet away when it cannot be set up',
        (tester) async {
      final printed = <String>[];
      final original = debugPrint;

      debugPrint =
          (String? message, {int? wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = original);
      walletSettingsApplier =
          (controller, applied) async => throw StateError('no web view');
      addTearDown(() => walletSettingsApplier = applyWalletSettings);

      await openSheet(tester, configuration());
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing);
      expect(
        printed,
        contains(contains('StateError')),
        reason: 'a debug build says what kind of failure it was',
      );
    });

    testWidgets('hands over when its own address answers an error',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      cardBox().navigation?.onHttpError?.call(
            HttpResponseError(
              request: WebResourceRequest(uri: Uri.parse(testFieldsPageUrl)),
              response: WebResourceResponse(
                uri: Uri.parse(testFieldsPageUrl),
                statusCode: 403,
              ),
            ),
          );
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.checkoutUnavailable);
    });

    testWidgets('takes the wallet away when its page does not load',
        (tester) async {
      await openSheet(tester, configuration());

      walletSurface().navigation?.onWebResourceError?.call(
            const WebResourceError(
              errorCode: -2,
              description: 'no connection',
              isForMainFrame: true,
            ),
          );
      await pumpFrames(tester);

      expect(find.byType(WalletSurface), findsNothing);
    });

    testWidgets('takes no charge while it loads again', (tester) async {
      await openSheet(tester, configuration());
      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      cardBox().navigation?.onPageStarted?.call(testFieldsPageUrl);
      await pumpFrames(tester);
      await tester.tap(find.text(r'Pay $97.42'), warnIfMissed: false);
      await pumpFrames(tester);

      expect(
        cardBox().scripts.where((script) => script.contains('.pay(')),
        isEmpty,
        reason: 'the page loading has no fields to take the charge',
      );
    });

    testWidgets('is started again when it loads again', (tester) async {
      await openSheet(tester, configuration());
      await completeTheCard(tester);
      cardBox().finishLoading();
      await pumpFrames(tester);

      expect(
        cardBox().scripts.where((script) => script.contains('.start(')),
        hasLength(2),
        reason: 'a page that reloaded has no fields until it is started',
      );
    });
  });

  group('a message the card box never asked for', () {
    String message(Map<String, Object?> event) => jsonEncode(event);

    testWidgets('hands an old card page over before anything is charged',
        (tester) async {
      final reasons = <FieldsError>[];
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false, onHandover: reasons.add),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      cardBox().postAsFrame(message(<String, Object?>{
        'type': 'ready',
        'amountMinor': 9742,
        'currency': 'USD',
      }));
      await pumpFrames(tester);

      expect(
        settled?.code,
        CheckoutResultCode.checkoutUnavailable,
        reason: 'a page that carries no key would never be heard answering',
      );
    });

    testWidgets('does not hold the sheet for a charge mark from a frame',
        (tester) async {
      final notes = <String>[];
      final pending =
          await openSheet(tester, configuration(onDiagnostic: notes.add));

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await completeTheCard(tester);
      cardBox().postAsFrame(message(<String, Object?>{'type': 'charging'}));
      await pumpFrames(tester);
      await tester.tap(find.byTooltip(const PaymentSheetStrings().close));
      await pumpFrames(tester);

      expect(
        settled?.status,
        CheckoutStatus.cancelled,
        reason: 'nothing was charged, and nothing the page said says so',
      );
      expect(notes, contains(startsWith('refused')));
    });

    testWidgets('says in the log that it could not read a message',
        (tester) async {
      final notes = <String>[];

      await openSheet(tester, configuration(onDiagnostic: notes.add));
      await completeTheCard(tester);
      cardBox().postAsFrame('not a message');
      await pumpFrames(tester);

      expect(notes, contains(startsWith('refused a message')));
    });

    testWidgets('says in the log why it kept its page from leaving',
        (tester) async {
      final notes = <String>[];

      await openSheet(tester, configuration(onDiagnostic: notes.add));
      await completeTheCard(tester);
      await cardBox().navigate('https://elsewhere.example/landing?code=1');
      await pumpFrames(tester);

      expect(
        notes,
        contains(
            allOf(contains('elsewhere.example'), isNot(contains('code=1')))),
      );
    });

    testWidgets('says in the log why it handed over', (tester) async {
      final notes = <String>[];

      await openSheet(
        tester,
        configuration(onDiagnostic: notes.add, fallBackToHostedCheckout: false),
      );
      cardBox().navigation?.onWebResourceError?.call(
            const WebResourceError(
              errorCode: -2,
              description: 'no connection',
              isForMainFrame: true,
            ),
          );
      await pumpFrames(tester);

      expect(notes, contains(contains('could not be loaded')));
    });

    testWidgets('says in the log why it dropped an answer', (tester) async {
      final notes = <String>[];

      await openSheet(tester, configuration(onDiagnostic: notes.add));
      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{
        'type': 'payment',
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(
        notes,
        contains(allOf(startsWith('refused'), contains('payment approved'))),
        reason: 'an answer dropped in silence leaves nothing to debug',
      );
    });

    testWidgets('is not reported as a payment', (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);

      postToCard(<String, Object?>{
        'type': 'payment',
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(
        settled,
        isNull,
        reason: 'no charge of the sheet was running, so nobody was paid',
      );
      expect(find.text(const PaymentSheetStrings().addNewCard), findsOneWidget);
    });

    /*
     * While the charge runs, the issuer's challenge is framed inside the box and can post
     * on the same channel as the page. Only the page was handed this charge's code.
     */
    testWidgets('is not reported as the payment while the charge runs',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{'type': 'charging'});

      for (final attempt in <String?>[null, 'not-the-code']) {
        postToCard(<String, Object?>{
          'type': 'payment',
          'success': true,
          'invoiceId': 90210,
          'paidStatus': 'PAID',
          if (attempt != null) 'attempt': attempt,
        });
      }
      await pumpFrames(tester);

      expect(settled, isNull,
          reason: 'neither carried the code of this charge');

      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(settled?.status, CheckoutStatus.paid);
    });

    /*
     * A failure frees the sheet: it ends the charge and offers the other ways to pay again.
     * One from a frame that was not handed this charge's code would do that while the
     * real charge can still go through.
     */
    testWidgets('is not taken as the failure of the charge that runs',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      await tester.tap(find.text(const PaymentSheetStrings().newCard));
      await pumpFrames(tester);
      await completeTheCard(tester);
      await tester.tap(find.text(r'Pay $97.42'));
      await pumpFrames(tester);
      postToCard(<String, Object?>{
        'type': 'authenticating',
        'stage': 'challenge',
      });

      for (final attempt in <String?>[null, 'not-the-code']) {
        postToCard(<String, Object?>{
          'type': 'error',
          'code': 'authentication_failed',
          'message': 'Made up',
          if (attempt != null) 'attempt': attempt,
        });
      }
      await pumpFrames(tester);

      expect(find.text('Made up'), findsNothing);
      expect(find.text(r'Pay $97.42'), findsNothing,
          reason: 'the charge is still running');

      answerTheCharge(<String, Object?>{
        'success': true,
        'invoiceId': 90210,
        'paidStatus': 'PAID',
      });
      await pumpFrames(tester);

      expect(settled?.status, CheckoutStatus.paid);
    });

    /*
     * A page sent elsewhere before it is ready never mounts its fields, and the box would
     * sit empty with nothing to say why. That is the same as a page on the wrong origin, and
     * is reported as one.
     */
    testWidgets(
        'falls back when the card page is sent elsewhere before it is ready',
        (tester) async {
      final pending = await openSheet(
        tester,
        configuration(fallBackToHostedCheckout: false),
      );

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      expect(
        await cardBox().navigate('https://elsewhere.example.com/card'),
        NavigationDecision.prevent,
      );
      await pumpFrames(tester);

      expect(settled?.code, CheckoutResultCode.checkoutUnavailable);
      expect(settled?.message, contains('registered origin'));
    });

    testWidgets('hands over once however often the page is sent elsewhere',
        (tester) async {
      final reasons = <FieldsError>[];

      (await openSheet(
        tester,
        configuration(onHandover: reasons.add),
        withProvider: true,
      ))
          .ignore();

      await cardBox().navigate('https://elsewhere.example.com/card');
      await cardBox().navigate('https://elsewhere.example.com/again');
      await pumpFrames(tester);
      await pumpFrames(tester);

      expect(reasons.single.failure, FieldsFailure.originNotAllowed);
      expect(launcher.launches, hasLength(1));
    });

    testWidgets('refuses a top-frame page from outside the registered origin',
        (tester) async {
      final pending = await openSheet(tester, configuration());

      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));

      postToCard(<String, Object?>{
        'type': 'ready',
        'amountMinor': 9742,
        'currency': 'USD'
      });
      await pumpFrames(tester);

      expect(
        await cardBox().navigate('https://elsewhere.example.com/card'),
        NavigationDecision.prevent,
      );
      expect(
        await cardBox().navigate(testFieldsPageUrl),
        NavigationDecision.navigate,
      );
      await pumpFrames(tester);

      expect(
        settled,
        isNull,
        reason: 'a live box is refused the navigation and carries on',
      );
    });

    testWidgets('lets the gateway and the issuer render their own frames',
        (tester) async {
      await openSheet(tester, configuration());

      expect(
        await cardBox()
            .navigate('https://3ds.issuer.example/step', isMainFrame: false),
        NavigationDecision.navigate,
      );
    });
  });
}
