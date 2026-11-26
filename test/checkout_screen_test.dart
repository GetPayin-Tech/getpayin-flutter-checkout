import 'dart:async';

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

/// The in-app screen, driven the way a real web view drives it.
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

  /// Pumps the frames a route transition needs.
  ///
  /// Not `pumpAndSettle`: the checkout draws a loading indicator until the page loads, and
  /// an indeterminate indicator animates for ever, so settling never happens.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  /// Mounts the provider under a navigator, the way an app does.
  Future<void> mountApp(WidgetTester tester) {
    return tester.pumpWidget(
      const MaterialApp(home: GetPayInProvider(child: Text('shop'))),
    );
  }

  testWidgets('shows the checkout and completes with what the return link said',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
        expectedInvoiceId: 'INV-1',
        title: 'Pay for Gold Plan',
      ),
    );

    await pumpFrames(tester);

    expect(find.text('Pay for Gold Plan'), findsOneWidget);
    expect(find.text(defaultCloseLabel), findsOneWidget);
    expect(webView.loadedUri, Uri.parse(testCheckoutUrl));

    webView.finishLoading();
    await pumpFrames(tester);

    final decision = await webView.navigate(
      returnLink('success=1&invoice_id=INV-1&invoice_status=PAID'),
    );

    expect(decision, NavigationDecision.prevent);
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.paid);
    expect(result.invoiceId, 'INV-1');
    expect(find.text('Pay for Gold Plan'), findsNothing);
    expect(find.text('shop'), findsOneWidget);
    expect(GetPayInCheckout.busy, isFalse);
  });

  testWidgets('lets the checkout page itself load', (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    expect(
        await webView.navigate(testCheckoutUrl), NavigationDecision.navigate);

    await webView.navigate(returnLink('success=0&message=Card+declined'));
    await pumpFrames(tester);

    expect((await pending).message, 'Card declined');
  });

  testWidgets('reports a closed screen as cancelled', (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
          returnUrl: testReturnUrl,
          presentation: CheckoutPresentation.inApp,
          closeLabel: 'Fermer'),
    );

    await pumpFrames(tester);
    await tester.tap(find.text('Fermer'));
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.cancelled);
    expect(result.message, closedByPayerMessage);
    expect(find.text('shop'), findsOneWidget);
  });

  testWidgets('reports the system back button as cancelled', (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);
    await tester.binding.handlePopRoute();
    await pumpFrames(tester);

    expect((await pending).status, CheckoutStatus.cancelled);
  });

  testWidgets('hides the top bar when the caller asks', (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
          returnUrl: testReturnUrl,
          presentation: CheckoutPresentation.inApp,
          headerShown: false),
    );

    await pumpFrames(tester);

    expect(find.text(defaultCheckoutTitle), findsNothing);

    await webView.navigate(returnLink('success=1'));
    await pumpFrames(tester);
    await pending;
  });

  /*
   * A checkout that cannot load would otherwise be a blank screen with no way out, and the
   * session would stay busy for the rest of the process.
   */
  testWidgets('shows a failure its own way out, even with the top bar hidden',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      'http://pay.getpayin.com/checkout/abc',
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
        headerShown: false,
        loadErrorMessage: 'Le paiement est indisponible.',
      ),
    );

    await pumpFrames(tester);

    webView.failLoading();
    await pumpFrames(tester);

    expect(find.text('Le paiement est indisponible.'), findsOneWidget);
    expect(find.text(defaultCloseLabel), findsOneWidget);

    await tester.tap(find.text(defaultCloseLabel));
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.cancelled);
    expect(result.message, 'Le paiement est indisponible.');
    expect(GetPayInCheckout.busy, isFalse);
  });

  testWidgets(
      'reports an unusable checkout URL rather than drawing a blank screen',
      (tester) async {
    final completed = <CheckoutResult>[];
    final failures = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: GetPayInCheckoutView(
          checkoutUrl: 'myapp://not-a-checkout',
          returnUrl: testReturnUrl,
          onComplete: completed.add,
          onLoadError: (message, detail) => failures.add('$message | $detail'),
        ),
      ),
    );

    await pumpFrames(tester);

    expect(webView.loadedUri, Uri.parse('about:blank'));
    expect(failures.single, contains(defaultLoadErrorMessage));
    expect(failures.single, contains('checkoutUrl'));
    expect(completed, isEmpty);
  });

  /*
   * The detail reaches the app's log. A bank's link can carry its own one-time values, so
   * the detail names where the link pointed and nothing that followed.
   */
  testWidgets('names a link the phone could not open without what it carried',
      (tester) async {
    final failures = <String>[];

    launcher.opens = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GetPayInCheckoutView(
          checkoutUrl: testCheckoutUrl,
          returnUrl: testReturnUrl,
          onComplete: (_) {},
          onLoadError: (message, detail) => failures.add('$detail'),
        ),
      ),
    );
    await pumpFrames(tester);
    await webView.navigate('mybank://authorise/3ds/1?otp=123456');
    await pumpFrames(tester);

    expect(failures.single, contains('mybank://authorise'));
    expect(failures.single, isNot(contains('otp')));
    expect(failures.single, isNot(contains('3ds')));
  });

  testWidgets('says so when it is mounted where no navigator can be reached',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: GetPayInProvider(child: Text('no navigator')),
      ),
    );

    await expectLater(
      GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(
          returnUrl: testReturnUrl,
          presentation: CheckoutPresentation.inApp,
        ),
      ),
      throwsA(isA<GetPayInProviderMissingError>()),
    );
    expect(GetPayInCheckout.busy, isFalse);
  });

  testWidgets('settles an open checkout when the provider goes away',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);
    await tester.pumpWidget(const MaterialApp(home: Text('gone')));

    final result = await pending;

    expect(result.status, CheckoutStatus.cancelled);
    expect(result.message, closedByUnmountMessage);
  });

  /*
   * A provider inside a nested navigator (a router shell, a tab) presents on the root one,
   * which outlives it. The checkout settles as the provider goes; the screen it left on the
   * root navigator must go with it, or the payer could still pay on a screen whose close
   * button no longer reaches anything.
   */
  testWidgets('takes its screen away when it goes while the screen stays',
      (tester) async {
    final shellShown = ValueNotifier<bool>(true);

    addTearDown(shellShown.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: shellShown,
          builder: (context, shown, _) => shown
              ? Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const GetPayInProvider(child: Text('shop')),
                  ),
                )
              : const Text('elsewhere'),
        ),
      ),
    );

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    expect(find.byType(GetPayInCheckoutView), findsOneWidget);

    shellShown.value = false;
    await pumpFrames(tester);

    final result = await pending;

    expect(result.status, CheckoutStatus.cancelled);
    expect(result.message, closedByUnmountMessage);
    expect(find.byType(GetPayInCheckoutView), findsNothing);
    expect(find.text('elsewhere'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /*
   * An app can take the checkout screen away in its own code, and neither a pop nor a reset
   * of its screens asks the screen first. Left unsettled, `open()` would never return and
   * every later checkout would be refused as busy.
   */
  group('a checkout screen the app takes away', () {
    const options = OpenCheckoutOptions(
      returnUrl: testReturnUrl,
      presentation: CheckoutPresentation.inApp,
    );

    NavigatorState navigator(WidgetTester tester) =>
        tester.state<NavigatorState>(find.byType(Navigator).first);

    /// Mounts the provider above the app's navigator, the setup a reset leaves standing.
    Future<void> mountAboveNavigator(WidgetTester tester) {
      final key = GlobalKey<NavigatorState>();

      return tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          builder: (context, child) =>
              GetPayInProvider(navigatorKey: key, child: child),
          home: const Text('shop'),
        ),
      );
    }

    testWidgets('settles when the app pops it', (tester) async {
      await mountApp(tester);

      CheckoutResult? settled;

      unawaited(
        GetPayInCheckout.open(testCheckoutUrl, options)
            .then((result) => settled = result),
      );
      await pumpFrames(tester);
      navigator(tester).pop();
      await pumpFrames(tester);

      expect(settled?.status, CheckoutStatus.cancelled);
      expect(settled?.message, closedByAppMessage);
      expect(GetPayInCheckout.busy, isFalse);
      expect(find.text('shop'), findsOneWidget);
    });

    testWidgets('settles when the app resets its screens', (tester) async {
      await mountAboveNavigator(tester);

      CheckoutResult? settled;

      unawaited(
        GetPayInCheckout.open(testCheckoutUrl, options)
            .then((result) => settled = result),
      );
      await pumpFrames(tester);
      unawaited(
        navigator(tester).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const Text('signed out')),
          (route) => false,
        ),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(settled?.status, CheckoutStatus.cancelled);
      expect(settled?.message, closedByAppMessage);
      expect(GetPayInCheckout.busy, isFalse);
      expect(find.text('signed out'), findsOneWidget);
    });

    testWidgets('settles without touching a navigator that is going away',
        (tester) async {
      await mountAboveNavigator(tester);

      CheckoutResult? settled;

      unawaited(
        GetPayInCheckout.open(testCheckoutUrl, options)
            .then((result) => settled = result),
      );
      await pumpFrames(tester);
      await tester.pumpWidget(const MaterialApp(home: Text('gone')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(settled?.status, CheckoutStatus.cancelled);
    });

    testWidgets('leaves a checkout opened while it is still leaving alone',
        (tester) async {
      await mountApp(tester);

      final first = GetPayInCheckout.open(testCheckoutUrl, options);

      await pumpFrames(tester);
      await tester.tap(find.text(defaultCloseLabel));
      await tester.pump();

      expect((await first).message, closedByPayerMessage);

      CheckoutResult? second;

      unawaited(
        GetPayInCheckout.open(testCheckoutUrl, options)
            .then((result) => second = result),
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(
        second,
        isNull,
        reason: 'the first screen finished leaving after the second had opened',
      );
      expect(GetPayInCheckout.busy, isTrue);
      expect(find.text(defaultCloseLabel), findsOneWidget);

      await tester.tap(find.text(defaultCloseLabel));
      await pumpFrames(tester);

      expect(second?.message, closedByPayerMessage);
    });
  });

  testWidgets('hands a 3-D Secure bank step to the phone', (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    expect(
      await webView.navigate('mybank://authorise/3ds/1'),
      NavigationDecision.prevent,
    );
    await pumpFrames(tester);

    expect(launcher.launches.single.$1, 'mybank://authorise/3ds/1');
    expect(find.text(defaultLinkErrorMessage), findsNothing);

    await webView.navigate(returnLink('success=1'));
    await pumpFrames(tester);
    await pending;
  });

  /*
   * A bank app that is not installed would otherwise leave the payer on a checkout whose
   * button does nothing, with no way out when the top bar is hidden.
   */
  testWidgets('tells the payer when the phone cannot open the bank app',
      (tester) async {
    await mountApp(tester);
    launcher.opens = false;

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
        headerShown: false,
        linkErrorMessage: "L'application bancaire est introuvable.",
      ),
    );

    await pumpFrames(tester);
    await webView.navigate('mybank://authorise/3ds/1');
    await pumpFrames(tester);

    expect(
        find.text("L'application bancaire est introuvable."), findsOneWidget);
    expect(find.text(defaultCloseLabel), findsOneWidget);

    await tester.tap(find.text(defaultCloseLabel));
    await pumpFrames(tester);

    expect((await pending).status, CheckoutStatus.cancelled);
  });

  /*
   * A failure once the checkout page has loaded can come after the charge: the payer may
   * have paid, and the page that would have said so is the one that failed. So the checkout
   * stays where it is under the message, and closing then cannot be "nothing happened".
   */
  group('a failure after the checkout has loaded', () {
    const options = OpenCheckoutOptions(
      returnUrl: testReturnUrl,
      presentation: CheckoutPresentation.inApp,
    );

    Future<Future<CheckoutResult>> failAfterLoading(WidgetTester tester) async {
      await mountApp(tester);

      final pending = GetPayInCheckout.open(testCheckoutUrl, options);

      await pumpFrames(tester);
      webView.finishLoading();
      await pumpFrames(tester);
      webView.failLoading();
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('is closed as unconfirmed, never as cancelled', (tester) async {
      final pending = await failAfterLoading(tester);

      expect(find.text(defaultLoadErrorMessage), findsOneWidget);

      await tester.tap(find.text(defaultCloseLabel));
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
      expect(result.message, defaultLoadErrorMessage);
    });

    testWidgets('is unconfirmed when the app takes the screen away too',
        (tester) async {
      final pending = await failAfterLoading(tester);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
      expect(result.message, defaultLoadErrorMessage);
      expect(GetPayInCheckout.busy, isFalse);
    });

    testWidgets('is unconfirmed when the provider goes with the screen',
        (tester) async {
      final pending = await failAfterLoading(tester);

      await tester.pumpWidget(const MaterialApp(home: Text('gone')));

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
      expect(result.message, defaultLoadErrorMessage);
    });

    testWidgets('keeps the checkout under the message for a late answer',
        (tester) async {
      final pending = await failAfterLoading(tester);

      expect(find.byType(GetPayInCheckoutView), findsOneWidget);

      await webView.navigate(
        returnLink('success=1&invoice_id=INV-1&invoice_status=PAID'),
      );
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });
  });

  /*
   * Android's `intent:` links name the app they are for, and the web page to show when no
   * app takes them, but no app answers to `intent:` as written.
   */
  group('an intent link from a bank step', () {
    const fallback = 'https://bank.example/3ds?ref=1';
    const link = 'intent://auth/3ds#Intent;scheme=mybank;package=com.bank;'
        'S.browser_fallback_url=https%3A%2F%2Fbank.example%2F3ds%3Fref%3D1;end';

    Future<void> openOnBankStep(WidgetTester tester) async {
      await mountApp(tester);
      GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(
          returnUrl: testReturnUrl,
          presentation: CheckoutPresentation.inApp,
        ),
      ).ignore();
      await pumpFrames(tester);
      webView.finishLoading();
      await webView.navigate(link);
      await pumpFrames(tester);
    }

    testWidgets('opens the app it names', (tester) async {
      await openOnBankStep(tester);

      expect(launcher.launches.single.$1, 'mybank://auth/3ds');
      expect(find.text(defaultLinkErrorMessage), findsNothing);
    });

    testWidgets('loads its web page when no app takes it', (tester) async {
      launcher.opens = false;
      await openOnBankStep(tester);

      expect(webView.loadedUri, Uri.parse(fallback));
      expect(find.text(defaultLinkErrorMessage), findsNothing);
    });

    testWidgets(
        'goes straight to its web page when it names no app it may open',
        (tester) async {
      await mountApp(tester);
      GetPayInCheckout.open(
        testCheckoutUrl,
        const OpenCheckoutOptions(
          returnUrl: testReturnUrl,
          presentation: CheckoutPresentation.inApp,
        ),
      ).ignore();
      await pumpFrames(tester);
      webView.finishLoading();
      await webView.navigate(
        'intent://x#Intent;scheme=market;'
        'S.browser_fallback_url=https%3A%2F%2Fbank.example%2F3ds%3Fref%3D1;end',
      );
      await pumpFrames(tester);

      expect(launcher.launches, isEmpty);
      expect(webView.loadedUri, Uri.parse(fallback));
    });

    testWidgets('loads its web page only into the checkout it came from',
        (tester) async {
      final answer = Completer<bool>();

      Widget view(String checkoutUrl) => MaterialApp(
            home: GetPayInCheckoutView(
              checkoutUrl: checkoutUrl,
              returnUrl: testReturnUrl,
              onComplete: (_) {},
            ),
          );

      launcher.answer = answer;
      await tester.pumpWidget(view(testCheckoutUrl));
      await pumpFrames(tester);

      final first = webView.controllers.last;

      webView.finishLoading();
      await webView.navigate(link);
      await tester.pumpWidget(view('$testCheckoutUrl?next=1'));
      await pumpFrames(tester);

      final second = webView.controllers.last;

      expect(second, isNot(same(first)));

      answer.complete(false);
      await pumpFrames(tester);

      expect(
        second.loaded,
        isNot(contains(Uri.parse(fallback))),
        reason: "one payer's bank page has no place in another's checkout",
      );
    });
  });

  testWidgets('carries on through a load the web view only cancelled',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);
    webView.finishLoading();
    webView.failLoading(errorCode: -999);
    await pumpFrames(tester);

    expect(find.text(defaultLoadErrorMessage), findsNothing);

    await webView.navigate(
      returnLink('success=1&invoice_id=INV-1&invoice_status=PAID'),
    );
    await pumpFrames(tester);

    expect((await pending).status, CheckoutStatus.paid);
  });

  test('never tells the payer to try again, or that nothing was charged', () {
    for (final text in <String>[
      defaultLoadErrorMessage,
      defaultLinkErrorMessage,
    ]) {
      expect(text.toLowerCase(), isNot(contains('try again')));
      expect(text.toLowerCase(), isNot(contains('nothing has been charged')));
    }
  });

  testWidgets('reports an HTTP error on the page the payer is on',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    webView.startLoading(testCheckoutUrl);
    webView.httpError(uri: 'https://analytics.example/collect', status: 404);
    await pumpFrames(tester);

    expect(find.text(defaultLoadErrorMessage), findsNothing);

    webView.httpError(uri: testCheckoutUrl);
    await pumpFrames(tester);

    expect(find.text(defaultLoadErrorMessage), findsOneWidget);

    await tester.tap(find.text(defaultCloseLabel));
    await pumpFrames(tester);
    await pending;
  });

  testWidgets('reports an iPhone HTTP error, which names no address',
      (tester) async {
    await mountApp(tester);

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);
    webView.startLoading(testCheckoutUrl);
    webView.delegate?.onHttpError?.call(
      HttpResponseError(
        response: WebResourceResponse(uri: null, statusCode: 502),
      ),
    );
    await pumpFrames(tester);

    expect(
      find.text(defaultLoadErrorMessage),
      findsOneWidget,
      reason: 'before the first page is up, an error answer is that page',
    );

    await tester.tap(find.text(defaultCloseLabel));
    await pumpFrames(tester);
    await pending;
  });

  testWidgets('reports a page the web view could not even be asked to load', (
    tester,
  ) async {
    final failures = <String>[];

    webView.loadFailure = StateError('no web view');

    await tester.pumpWidget(
      MaterialApp(
        home: GetPayInCheckoutView(
          checkoutUrl: testCheckoutUrl,
          returnUrl: testReturnUrl,
          onComplete: (_) {},
          onLoadError: (message, detail) => failures.add('$message | $detail'),
        ),
      ),
    );

    await pumpFrames(tester);

    expect(failures.single, contains(defaultLoadErrorMessage));
    expect(failures.single, contains('no web view'));
  });

  /*
   * A page can go to a return link that names another invoice: a stale checkout, or a
   * made-up link. It is not this checkout's answer, so the screen goes on; and because the
   * real payment may still be running, a close after it cannot be "nothing happened".
   */
  group('a return link naming another invoice', () {
    const options = OpenCheckoutOptions(
      returnUrl: testReturnUrl,
      presentation: CheckoutPresentation.inApp,
      expectedInvoiceId: 'INV-1',
    );

    Future<Future<CheckoutResult>> passOver(WidgetTester tester) async {
      await mountApp(tester);

      final pending = GetPayInCheckout.open(testCheckoutUrl, options);

      await pumpFrames(tester);
      webView.finishLoading();
      await pumpFrames(tester);

      expect(
        await webView.navigate(returnLink('success=0&invoice_id=INV-OTHER')),
        NavigationDecision.prevent,
      );
      await pumpFrames(tester);

      return pending;
    }

    testWidgets('leaves the checkout on screen', (tester) async {
      final pending = await passOver(tester);
      CheckoutResult? settled;

      unawaited(pending.then((result) => settled = result));
      await pumpFrames(tester);

      expect(settled, isNull);
      expect(find.byType(GetPayInCheckoutView), findsOneWidget);
    });

    testWidgets('still settles on the link that names its invoice',
        (tester) async {
      final pending = await passOver(tester);

      await webView.navigate(returnLink('success=1&invoice_id=INV-1'));
      await pumpFrames(tester);

      expect((await pending).status, CheckoutStatus.paid);
    });

    testWidgets('is closed as unconfirmed after it, never as cancelled',
        (tester) async {
      final pending = await passOver(tester);

      await tester.tap(find.text(defaultCloseLabel));
      await pumpFrames(tester);

      final result = await pending;

      expect(result.status, CheckoutStatus.notPaid);
      expect(result.code, CheckoutResultCode.outcomeUnknown);
    });
  });

  testWidgets('starts a new checkout when the checkout URL changes',
      (tester) async {
    final results = <CheckoutResult>[];

    Widget view(String checkoutUrl) {
      return MaterialApp(
        home: GetPayInCheckoutView(
          checkoutUrl: checkoutUrl,
          returnUrl: testReturnUrl,
          onComplete: results.add,
        ),
      );
    }

    await tester.pumpWidget(view(testCheckoutUrl));
    await pumpFrames(tester);
    await webView.navigate(returnLink('success=1&invoice_id=FIRST'));

    await tester.pumpWidget(view('$testCheckoutUrl?attempt=2'));
    await pumpFrames(tester);
    await webView.navigate(returnLink('success=1&invoice_id=SECOND'));

    expect(
      results.map((result) => result.invoiceId),
      <String>['FIRST', 'SECOND'],
    );
    expect(webView.loadedUri, Uri.parse('$testCheckoutUrl?attempt=2'));
  });

  /*
   * The old web view goes on running for a moment after a new checkout replaces it, and its
   * page can still navigate or fail. None of that is the new checkout's.
   */
  testWidgets('ignores the old web view once a new checkout has started',
      (tester) async {
    final results = <CheckoutResult>[];
    final failures = <String>[];
    var pagesLoaded = 0;

    Widget view(String checkoutUrl) {
      return MaterialApp(
        home: GetPayInCheckoutView(
          checkoutUrl: checkoutUrl,
          returnUrl: testReturnUrl,
          onComplete: results.add,
          onLoadError: (message, _) => failures.add(message),
          onPageLoaded: () => pagesLoaded += 1,
        ),
      );
    }

    await tester.pumpWidget(view(testCheckoutUrl));
    await pumpFrames(tester);

    final old = webView.controllers.last;

    await tester.pumpWidget(view('$testCheckoutUrl?attempt=2'));
    await pumpFrames(tester);

    expect(
      await old.navigate(returnLink('success=0&invoice_id=FIRST')),
      NavigationDecision.prevent,
    );
    old.finishLoading();
    old.navigation?.onWebResourceError?.call(
      const WebResourceError(errorCode: -1, description: 'gone'),
    );
    await pumpFrames(tester);

    expect(results, isEmpty, reason: 'the new checkout is still running');
    expect(failures, isEmpty);
    expect(pagesLoaded, 0);

    await webView.navigate(returnLink('success=1&invoice_id=SECOND'));

    expect(results.single.invoiceId, 'SECOND');
  });

  /*
   * The app can push a screen of its own over the checkout — a confirmation sheet, a
   * notification tap — and the checkout still has to come off the stack when it ends.
   */
  testWidgets(
      'takes the checkout away even when it is no longer the top screen', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: GetPayInProvider(child: const Text('shop')),
      ),
    );

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    unawaited(
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('on top')),
      ),
    );
    await pumpFrames(tester);

    expect(find.text('on top'), findsOneWidget);

    await webView.navigate(returnLink('success=1&invoice_id=INV-1'));
    await pumpFrames(tester);

    expect((await pending).status, CheckoutStatus.paid);
    expect(find.text('on top'), findsOneWidget);
    expect(find.text(defaultCheckoutTitle), findsNothing);
  });

  /*
   * An app that mounts the provider in MaterialApp.builder, or in a router shell, has it
   * above the navigator it must present on. The key is how it reaches that navigator.
   */
  testWidgets('presents on the navigator it was handed a key for',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) =>
            GetPayInProvider(navigatorKey: navigatorKey, child: child),
        home: const Text('shop'),
      ),
    );

    final pending = GetPayInCheckout.open(
      testCheckoutUrl,
      const OpenCheckoutOptions(
        returnUrl: testReturnUrl,
        presentation: CheckoutPresentation.inApp,
      ),
    );

    await pumpFrames(tester);

    expect(find.text(defaultCheckoutTitle), findsOneWidget);

    await webView.navigate(returnLink('success=1&invoice_id=INV-1'));
    await pumpFrames(tester);

    expect((await pending).status, CheckoutStatus.paid);
    expect(find.text('shop'), findsOneWidget);
  });
}
