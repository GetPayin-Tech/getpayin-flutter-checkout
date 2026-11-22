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
