import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

import 'support/fixtures.dart';

/*
 * Any app or web page on the phone can invoke the return scheme with whatever query it
 * likes, and a compromised checkout page can drive the web view at any URL it likes. These
 * are the shapes that would be worth trying: a near-miss host that the matcher might
 * accept, and a status the reader might upgrade to paid.
 */

/// The page itself navigating, in an app with no extra schemes.
NavigationContext fromPage({bool isTopFrame = true}) {
  return NavigationContext(returnUrl: testReturnUrl, isTopFrame: isTopFrame);
}

void main() {
  group('a forged link must not pass as the return link', () {
    const forged = <(String, String)>[
      (
        'userinfo before the real host',
        'myapp://payment-return@evil.example.com'
      ),
      (
        'the host as userinfo of another',
        'myapp://evil.example.com@payment-return.evil'
      ),
      (
        'a longer host with the same prefix',
        'myapp://payment-return.evil.example.com'
      ),
      ('a host the return host is a suffix of', 'myapp://evil-payment-return'),
      (
        'an extra path segment',
        'myapp://payment-return/../payment-return/evil'
      ),
      ('a deeper path', 'myapp://payment-return/evil'),
      ('another scheme entirely', 'https://payment-return'),
      ('a scheme that contains the real one', 'notmyapp://payment-return'),
      ('a port on the authority', 'myapp://payment-return:8080'),
      ('backslashes instead of slashes', r'myapp:\\payment-return'),
      ('a percent-encoded host', 'myapp://payment%2Dreturn'),
      (
        'an empty authority with the host in the path',
        'myapp:///payment-return'
      ),
    ];

    for (final (label, url) in forged) {
      test('rejects $label', () {
        expect(matchesReturnUrl(url, testReturnUrl), isFalse);
      });
    }

    test('still accepts the genuine link with a query and fragment', () {
      expect(
          matchesReturnUrl('myapp://payment-return?success=1#x', testReturnUrl),
          isTrue);
    });
  });

  group('a forged link must not read as paid', () {
    const forged = <(String, String)>[
      ('an empty success flag', 'myapp://payment-return?success='),
      (
        'a success flag of its own invention',
        'myapp://payment-return?success=yes'
      ),
      ('no parameters at all', 'myapp://payment-return'),
      (
        'a flag buried in another key',
        'myapp://payment-return?note=success%3D1'
      ),
      (
        'a status field GetPayIn never sends',
        'myapp://payment-return?status=paid'
      ),
      (
        'a state field GetPayIn never sends',
        'myapp://payment-return?state=approved'
      ),
      ('a success array suffix', 'myapp://payment-return?success[]=1'),
    ];

    for (final (label, url) in forged) {
      test('does not report $label as paid', () {
        expect(readCheckoutResult(url).status, isNot(CheckoutStatus.paid));
      });
    }

    test('does not let a later repeated flag overwrite the first', () {
      expect(
        readCheckoutResult('myapp://payment-return?success=0&success=1').status,
        CheckoutStatus.notPaid,
      );
    });

    test('does not let a status field overrule the success flag', () {
      expect(
        readCheckoutResult('myapp://payment-return?status=paid&success=0')
            .status,
        CheckoutStatus.notPaid,
      );
    });
  });

  group('a hostile navigation must not reach the phone as an app link', () {
    const scripts = <String>[
      'javascript:alert(document.cookie)',
      'JaVaScRiPt:alert(1)',
      'file:///etc/passwd',
      'data:text/html,<script>alert(1)</script>',
    ];

    for (final url in scripts) {
      test('keeps $url inside the web view rather than handing it to the phone',
          () {
        expect(
          classifyNavigation(url, fromPage()),
          isNot(NavigationVerdict.openExternally),
        );
      });
    }

    const refused = <String>[
      'market://details?id=evil.app',
      'sms:+15550100?body=TRANSFER%20500',
      'shortcuts://run-shortcut?name=Pay',
    ];

    for (final url in refused) {
      test(
          'refuses $url, which a browser would not open from the same page either',
          () {
        expect(classifyNavigation(url, fromPage()), NavigationVerdict.block);
      });
    }

    /*
     * The 3-D Secure page is the issuer's, not GetPayIn's, and it knows the real invoice
     * id, so a frame it embeds must not be able to end the checkout or reach another app.
     */
    const fromFrame = <String>[
      'myapp://payment-return?success=1&invoice_id=4512',
      'mybank://authorise/3ds/9',
    ];

    for (final url in fromFrame) {
      test('refuses $url when a frame inside the page asks for it', () {
        expect(
          classifyNavigation(url, fromPage(isTopFrame: false)),
          NavigationVerdict.block,
        );
      });
    }
  });
}
