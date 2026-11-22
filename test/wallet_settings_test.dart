import 'package:flutter/foundation.dart';
// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/webview/wallet_settings.dart';

import 'support/fake_webview.dart';
import 'support/fixtures.dart';

/*
 * Android turns the Payment Request API off in every web view, and Google Pay is built on
 * it. A surface that renders a wallet without asking for it back is told there is no
 * wallet, draws nothing, and reports nothing — which is indistinguishable from a company
 * that does not sell the wallet at all.
 */
void main() {
  late FakeWebViewPlatform webView;
  late List<CheckoutWebViewSettings> applied;
  late List<bool> beforeTheLoad;

  setUp(() {
    webView = FakeWebViewPlatform.install();
    applied = <CheckoutWebViewSettings>[];
    beforeTheLoad = <bool>[];

    walletSettingsApplier = (controller, settings) async {
      applied.add(settings);
      beforeTheLoad.add(webView.controllers.every((c) => c.loaded.isEmpty));
    };
  });

  tearDown(() {
    walletSettingsApplier = applyWalletSettings;
  });

  group('the wallet surface', () {
    /// Pumps the surface as an Android build, and is an Android build no longer.
    ///
    /// A widget test checks the foundation's debug variables before its own tearDown runs,
    /// so the override has to be put back inside the test body rather than after it.
    Future<void> pumpSurface(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(
        MaterialApp(
          home: WalletSurface(
            session: testFieldsSession(),
            pageUrl: testFieldsPageUrl,
            wallet: PaymentWallet.googlePay,
            returnUrl: testReturnUrl,
            onComplete: (_) {},
          ),
        ),
      );
      await tester.pump();

      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('asks for the Payment Request API Google Pay needs',
        (tester) async {
      await pumpSurface(tester);

      expect(applied, hasLength(1));
      expect(applied.single.paymentRequestEnabled, isTrue);
    });

    testWidgets('asks before the page loads, which is the only time it counts',
        (tester) async {
      await pumpSurface(tester);

      expect(beforeTheLoad, <bool>[true]);
      expect(webView.controllers.first.loaded, isNotEmpty);
    });
  });
}
