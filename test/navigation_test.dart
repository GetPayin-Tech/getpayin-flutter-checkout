import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

import 'support/fixtures.dart';

/// The ordinary case: the page itself navigating.
NavigationContext topFrame([List<String> ownSchemes = const <String>[]]) {
  return NavigationContext(
    returnUrl: testReturnUrl,
    ownSchemes: ownSchemes,
    isTopFrame: true,
  );
}

/// A frame inside the checkout page navigating.
NavigationContext subFrame([List<String> ownSchemes = const <String>[]]) {
  return NavigationContext(
    returnUrl: testReturnUrl,
    ownSchemes: ownSchemes,
    isTopFrame: false,
  );
}

void main() {
  group('classifyNavigation', () {
    test('ends the checkout on the return link', () {
      expect(
        classifyNavigation(returnLink('success=1'), topFrame()),
        NavigationVerdict.endCheckout,
      );
    });

    const web = <String>[
      'https://pay.getpayin.com/checkout/abc',
      'http://pay.getpayin.com/checkout/abc',
      'about:blank',
    ];

    for (final url in web) {
      test('keeps $url in the web view', () {
        expect(classifyNavigation(url, topFrame()), NavigationVerdict.load);
      });
    }

    const external = <String>[
      'mybank://authorise/3ds/123',
      'tel:+96512345678',
      'mailto:support@example.com',
      'intent://scan#Intent;scheme=zxing;end',
    ];

    for (final url in external) {
      test('hands $url to the phone', () {
        expect(classifyNavigation(url, topFrame()),
            NavigationVerdict.openExternally);
      });
    }

    const scripts = <String>[
      'javascript:alert(1)',
      'JAVASCRIPT:alert(1)',
      'vbscript:msgbox(1)'
    ];

    for (final url in scripts) {
      test('refuses $url outright rather than handing it to the phone', () {
        expect(classifyNavigation(url, topFrame()), NavigationVerdict.block);
      });
    }

    const nothingToDoWithPaying = <String>[
      'market://details?id=evil.app',
      'itms-apps://apps.apple.com/app/id1',
      'itms-services://?action=download-manifest',
      'sms:+15550100?body=TRANSFER%20500',
      'smsto:+15550100',
      'mms:+15550100',
      'shortcuts://run-shortcut?name=Pay',
      'content://com.android.providers/contacts',
      'android-app://com.other.app',
    ];

    for (final url in nothingToDoWithPaying) {
      test('refuses $url, which has no part in paying for anything', () {
        expect(classifyNavigation(url, topFrame()), NavigationVerdict.block);
      });
    }

    const ownRoutes = <String>[
      'myapp://account/delete?confirm=1',
      'myapp://settings',
      'MYAPP://payment-return/elsewhere',
    ];

    for (final url in ownRoutes) {
      test("refuses $url, so a page cannot drive the host app's own deep links",
          () {
        expect(classifyNavigation(url, topFrame()), NavigationVerdict.block);
      });
    }

    const declared = <String>[
      'com.shop.app://orders/1/cancel',
      'COM.SHOP.APP://settings',
      'myapp-ios://account',
    ];

    for (final url in declared) {
      test('refuses $url, another scheme the host app answers to', () {
        expect(
          classifyNavigation(
              url, topFrame(<String>['com.shop.app', 'MyApp-iOS'])),
          NavigationVerdict.block,
        );
      });
    }

    test('still hands a different app its own scheme', () {
      expect(
        classifyNavigation('mybank://authorise/3ds/1', topFrame()),
        NavigationVerdict.openExternally,
      );
      expect(
        classifyNavigation(
            'mybank://authorise/3ds/1', topFrame(<String>['com.shop.app'])),
        NavigationVerdict.openExternally,
      );
    });

    test('accepts a declared scheme written with its separator', () {
      expect(
        classifyNavigation(
            'shopdeep://orders', topFrame(<String>['shopdeep://'])),
        NavigationVerdict.block,
      );
    });

    test('keeps a relative navigation in the web view', () {
      expect(classifyNavigation('/checkout/step-2', topFrame()),
          NavigationVerdict.load);
    });

    test('refuses the return link from a frame inside the page', () {
      expect(
        classifyNavigation(returnLink('success=1&invoice_id=4512'), subFrame()),
        NavigationVerdict.block,
      );
    });

    test('refuses a bank app asked for by a frame inside the page', () {
      expect(
        classifyNavigation('mybank://authorise/3ds/9', subFrame()),
        NavigationVerdict.block,
      );
    });

    test('still lets a frame inside the page load ordinary web content', () {
      expect(
        classifyNavigation('https://3ds.issuer.example/step', subFrame()),
        NavigationVerdict.load,
      );
      expect(
          classifyNavigation('/challenge', subFrame()), NavigationVerdict.load);
    });
  });
}
