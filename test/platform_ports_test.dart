import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sessions/browser_session.dart';
import 'package:getpayin_checkout/src/sessions/deep_link.dart';
import 'package:getpayin_checkout/src/webview/external_link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/fake_launcher.dart';
import 'support/fakes.dart';
import 'support/fixtures.dart';

/// The calls that reach a plugin, with the plugin replaced.
void main() {
  late FakeUrlLauncher launcher;
  late FakeDeepLinks links;

  setUp(() {
    launcher = FakeUrlLauncher.install();
    links = FakeDeepLinks();
    returnLinkWatcher = ReturnLinkWatcher(source: links.source);
  });

  tearDown(() => links.dispose());

  group('openExternalLink', () {
    test('hands a bank app to the phone, in the app that owns the link',
        () async {
      var failed = false;

      await openExternalLink('mybank://authorise/3ds/1', () => failed = true);

      expect(launcher.launches, <(String, PreferredLaunchMode)>[
        ('mybank://authorise/3ds/1', PreferredLaunchMode.externalApplication),
      ]);
      expect(failed, isFalse);
    });

    /*
     * Asking first answers no for every scheme the host app has not declared, and no app
     * can declare every bank's scheme, so the step would silently do nothing.
     */
    test('never asks whether the link can be opened', () async {
      await openExternalLink('mybank://authorise/3ds/1', () {});

      expect(launcher.asked, isEmpty);
    });

    test('reports the failure when nothing on the phone can open it', () async {
      launcher.opens = false;
      var failed = false;

      await openExternalLink('mybank://authorise/3ds/1', () => failed = true);

      expect(failed, isTrue);
    });
  });

  group('BrowserCheckoutPorts.platform', () {
    test('opens the checkout in a real browser sheet', () async {
      await BrowserCheckoutPorts.platform().openSheet(testCheckoutUrl);

      expect(launcher.launches, <(String, PreferredLaunchMode)>[
        (testCheckoutUrl, PreferredLaunchMode.inAppBrowserView),
      ]);
    });

    test('reports a phone that cannot open a browser sheet at all', () async {
      launcher.opens = false;

      await expectLater(
        BrowserCheckoutPorts.platform().openSheet(testCheckoutUrl),
        throwsA(isA<GetPayInCheckoutError>()),
      );
    });

    test('closes the sheet', () async {
      await BrowserCheckoutPorts.platform().closeSheet();

      expect(launcher.closes, 1);
    });
  });

  /*
   * The app's lifecycle only moves through valid transitions, which is the sequence a
   * phone actually produces when a browser sheet covers the app and then goes away.
   */
  testWidgets('watchSheetDismissal reports the app coming back to the front', (
    tester,
  ) async {
    const away = <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const back = <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    var dismissals = 0;
    final watcher = BrowserCheckoutPorts.platform().watchDismissal(
      () => dismissals += 1,
    );

    for (final state in away) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    await tester.pump();

    expect(dismissals, 0);

    for (final state in back) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    await tester.pump();

    expect(dismissals, 1);

    watcher.stop();

    for (final state in <AppLifecycleState>[...away, ...back]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    await tester.pump();

    expect(dismissals, 1);
  });
}
