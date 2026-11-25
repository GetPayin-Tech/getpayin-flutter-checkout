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
    Duration successPause = Duration.zero,
    String origin = testOrigin,
  }) {
    return PaymentSheetConfiguration(
      collectBillingAddress: collectBillingAddress,
      onHandover: onHandover,
      successPause: successPause,
      session: testFieldsSession(origin: origin),
      fieldsPageUrl: testFieldsPageUrl,
      returnUrl: testReturnUrl,
      expectedInvoiceId: 90210,
      amountLabel: r'$97.42',
      wallets: wallets,
      savedCards: savedCards,
      chargeSavedCard: chargeSavedCard,
      fallBackToHostedCheckout: fallBackToHostedCheckout,
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

    expect(cardBox().scripts.last, contains('__paylinkHost.pay(null)'));

    postToCard(<String, Object?>{
      'type': 'payment',
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

  testWidgets('keeps the sheet open on a decline, with the reason',
      (tester) async {
    await openSheet(tester, configuration());

    await tester.tap(find.text(const PaymentSheetStrings().newCard));
    await pumpFrames(tester);
    await completeTheCard(tester);
    await tester.tap(find.text(r'Pay $97.42'));
    await pumpFrames(tester);

    postToCard(<String, Object?>{
      'type': 'payment',
      'success': false,
      'invoiceId': 90210,
      'message': 'Card declined',
    });
    await pumpFrames(tester);

    expect(find.text('Card declined'), findsOneWidget);
    expect(find.text(const PaymentSheetStrings().addNewCard), findsOneWidget);
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
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(
      box.width,
      screen.width,
      reason: 'the issuer formats its page for a window, and every point taken '
          'off the width is taken off the page',
    );
    expect(
      box.height,
      greaterThan(screen.height * 0.8),
      reason: 'a challenge drawn in a short box scrolls the field out of it',
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

      postToCard(<String, Object?>{
        'type': 'payment',
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

      postToCard(<String, Object?>{
        'type': 'payment',
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

      postToCard(<String, Object?>{
        'type': 'payment',
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

      postToCard(<String, Object?>{'type': 'charging'});
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('is not reported as a checkout that never ran', (tester) async {
      final pending = await startCharging(tester, fallBack: false);

      postToCard(<String, Object?>{
        'type': 'error',
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

      postToCard(<String, Object?>{
        'type': 'error',
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

      postToCard(<String, Object?>{
        'type': 'payment',
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
   * The card box talks to one page, over a channel everything that page frames can post on,
   * and no platform names the sender of a message. So it answers one charge, the one it
   * asked for, and gives its top frame to the registered origin and nothing else.
   */
  group('a message the card box never asked for', () {
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

    testWidgets('refuses a top-frame page from outside the registered origin',
        (tester) async {
      await openSheet(tester, configuration());

      expect(
        await cardBox().navigate('https://elsewhere.example.com/card'),
        NavigationDecision.prevent,
      );
      expect(
        await cardBox().navigate(testFieldsPageUrl),
        NavigationDecision.navigate,
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
