import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:url_launcher/url_launcher.dart';

import '../core/deferred.dart';
import '../core/messages.dart';
import '../core/return_url.dart';
import '../errors.dart';
import '../types.dart';
import 'deep_link.dart';
import 'dismissal.dart';
import 'watcher.dart';

/// How long a dismissed browser sheet waits for the return link before it is reported as
/// cancelled.
///
/// The sheet can go away before the deep link it was dismissed by reaches the app, and
/// settling on that order would report a payment the payer actually completed as cancelled.
const Duration deepLinkGrace = Duration(milliseconds: 600);

/// Starts watching for the return link and hands back how to stop.
typedef ReturnLinkWatch = CheckoutWatcher Function(
  String returnUrl,
  void Function(String url) onMatch,
);

/// Starts watching for the sheet being dismissed and hands back how to stop.
typedef DismissalWatch = CheckoutWatcher Function(void Function() onDismissed);

/// Everything the browser presentation needs from the phone.
///
/// Taken as a value so the ordering — open, then whichever of the return link and the
/// dismissal arrives first, then the grace period — is testable without a browser.
class BrowserCheckoutPorts {
  /// Creates the ports a browser checkout runs against.
  const BrowserCheckoutPorts({
    required this.openSheet,
    required this.closeSheet,
    required this.watchReturnLink,
    required this.watchDismissal,
    this.grace = deepLinkGrace,
  });

  /// The ports every app uses: `url_launcher` for the sheet, `app_links` for the return
  /// link, the app's own lifecycle for the dismissal.
  factory BrowserCheckoutPorts.platform() {
    return BrowserCheckoutPorts(
      openSheet: _openSheet,
      closeSheet: closeInAppWebView,
      watchReturnLink: returnLinkWatcher.watch,
      watchDismissal: watchSheetDismissal,
    );
  }

  /// Opens the checkout in the phone's browser sheet.
  final Future<void> Function(String url) openSheet;

  /// Closes the sheet, whatever state it is in.
  final Future<void> Function() closeSheet;

  /// Watches for the return link, calling back at most once.
  final ReturnLinkWatch watchReturnLink;

  /// Watches for the sheet being dismissed.
  final DismissalWatch watchDismissal;

  /// How long a dismissal waits for a return link that may be racing it.
  final Duration grace;
}

/// The ports a browser checkout runs against.
///
/// A variable rather than a constant so the suite can drive the whole sequence — open,
/// return link, dismissal, grace period — without a browser, and so an app with its own
/// browser plugin can swap one in. Built on first use, so a test that replaces it never
/// reaches a plugin at all.
BrowserCheckoutPorts browserCheckoutPorts = BrowserCheckoutPorts.platform();

/// Opens the sheet, treating "nothing could open it" as a failure of the checkout.
///
/// `LaunchMode.inAppBrowserView` is Chrome Custom Tabs on Android and
/// `SFSafariViewController` on iOS: a real browser, which is why Google Pay runs there with
/// no app approval at all.
Future<void> _openSheet(String url) async {
  final opened =
      await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

  if (!opened) {
    throw const GetPayInCheckoutError(
      'The phone could not open the checkout in a browser sheet.',
    );
  }
}

/// Opens the checkout in the phone's browser sheet and waits for the result.
///
/// This is the Android path until Google has approved the client's app: Google Pay runs in a
/// real browser without any approval, where in an app's own web view it does not.
Future<CheckoutResult> runBrowserCheckout(
  CheckoutRequest request, {
  BrowserCheckoutPorts? ports,
}) async {
  final phone = ports ?? browserCheckoutPorts;
  final options = request.options;
  final boundInvoiceId =
      invoiceBoundTo(options.expectedInvoiceId, request.checkoutUrl);
  final result = Deferred<CheckoutResult>();
  final dismissed = Deferred<void>();
  var passedOver = false;
  late CheckoutWatcher linkWatcher;

  void onLink(String url) {
    if (!returnLinkAnswers(url, expectedInvoiceId: boundInvoiceId)) {
      if (kDebugMode) {
        debugPrint(
          'GetPayIn: passed over a return link that names another invoice, or none',
        );
      }

      passedOver = true;
      linkWatcher.stop();
      linkWatcher = phone.watchReturnLink(options.returnUrl, onLink);

      return;
    }

    result.resolve(
      resolveReturn(url, expectedInvoiceId: boundInvoiceId),
    );
  }

  linkWatcher = phone.watchReturnLink(options.returnUrl, onLink);

  final dismissalWatcher = phone.watchDismissal(() => dismissed.resolve(null));

  try {
    await phone.openSheet(request.checkoutUrl);
    await Future.any<void>(<Future<void>>[result.future, dismissed.future]);

    if (result.settled) {
      return await result.future;
    }

    final arrived = await _withGrace(result.future, phone.grace);

    return arrived ??
        (passedOver
            ? _closedUnconfirmed
            : cancelledResult(closedByPayerMessage));
  } finally {
    linkWatcher.stop();
    dismissalWatcher.stop();
    await _ignoringFailure(phone.closeSheet);
  }
}

/// The result for a sheet that closed with no answer after it had passed over a link.
///
/// On Android any link to the app brings it to the front, and that reads exactly like the
/// payer closing the sheet. The payer may still be paying in the browser behind the app,
/// so the close is one nobody can confirm, never a cancel.
const CheckoutResult _closedUnconfirmed = CheckoutResult(
  status: CheckoutStatus.notPaid,
  code: CheckoutResultCode.outcomeUnknown,
  message: closedByPayerMessage,
);

/// The result if it arrives within [grace], or null when the grace period runs out first.
Future<CheckoutResult?> _withGrace(
    Future<CheckoutResult> pending, Duration grace) {
  final race = Deferred<CheckoutResult?>();
  final timer = Timer(grace, () => race.resolve(null));

  unawaited(
    pending.then((result) {
      timer.cancel();
      race.resolve(result);
    }),
  );

  return race.future;
}

/// Runs [work] and swallows any failure, for a call whose outcome changes nothing.
///
/// Closing a sheet that has already closed itself is the case: it reports a failure on some
/// platforms, and it is not a problem worth surfacing to the payer — least of all over a
/// result that has already been read.
Future<void> _ignoringFailure(Future<void> Function() work) async {
  try {
    await work();
  } catch (_) {
    return;
  }
}
