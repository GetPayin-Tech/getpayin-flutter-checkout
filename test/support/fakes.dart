import 'dart:async';

import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/sessions/browser_session.dart';
import 'package:getpayin_checkout/src/sessions/deep_link.dart';
import 'package:getpayin_checkout/src/sessions/watcher.dart';

/// Lets the event loop run, for a rule whose ordering is the thing under test.
Future<void> flush() async {
  for (var turn = 0; turn < 5; turn += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The two deep-link sources, under the test's control.
///
/// [initial] is a pull of state that persists, as the activity's intent is; [emit] is the
/// push the system makes when a link arrives while the app is running.
class FakeDeepLinks {
  final StreamController<Uri> _links = StreamController<Uri>.broadcast();

  /// What the initial-link reader answers, which it keeps answering until changed.
  String? initial;

  /// How many times the initial link has been read.
  int initialReads = 0;

  /// How many stream subscriptions are open, so a test can prove a watcher stopped.
  int get listeners => _links.hasListener ? 1 : 0;

  /// The source to hand a [ReturnLinkWatcher].
  DeepLinkSource get source => DeepLinkSource(
        initialLink: () async {
          initialReads += 1;

          final url = initial;

          return url == null ? null : Uri.parse(url);
        },
        links: () => _links.stream,
      );

  /// Delivers a link the way the system does while the app is running.
  void emit(String url) => _links.add(Uri.parse(url));

  /// Reports a failure on the link stream, as a plugin that loses its channel does.
  void fail(Object error) => _links.addError(error);

  /// Closes the stream, for a test that is done with it.
  Future<void> dispose() => _links.close();
}

/// The phone a browser checkout runs against, under the test's control.
class FakePhone {
  FakePhone({this.onOpened, Duration? grace})
      : grace = grace ?? const Duration(milliseconds: 20);

  /// Called once the sheet is open, which is where a test delivers what happens next.
  final void Function(FakePhone phone)? onOpened;

  /// How long a dismissal waits for a racing return link.
  final Duration grace;

  /// The checkout URLs the sheet was asked to open.
  final List<String> opened = <String>[];

  /// How many times the sheet was closed.
  int closes = 0;

  /// How many watchers were stopped, which must be one each by the time it ends.
  int stops = 0;

  /// Set to have opening the sheet fail, as a phone with no browser does.
  Object? openFailure;

  /// Set to have closing the sheet fail, as a sheet that already closed does.
  Object? closeFailure;

  String? _returnUrl;
  void Function(String url)? _onMatch;
  void Function()? _onDismissed;

  /// The ports [runBrowserCheckout] is given.
  BrowserCheckoutPorts get ports => BrowserCheckoutPorts(
        openSheet: _openSheet,
        closeSheet: _closeSheet,
        watchReturnLink: _watchReturnLink,
        watchDismissal: _watchDismissal,
        grace: grace,
      );

  /// Delivers a deep link, filtered the way the real watcher filters it.
  void deliver(String url) {
    final returnUrl = _returnUrl;

    if (returnUrl != null && matchesReturnUrl(url, returnUrl)) {
      _onMatch?.call(url);
    }
  }

  /// Reports the sheet going away, which is the app coming back to the front.
  void dismiss() => _onDismissed?.call();

  Future<void> _openSheet(String url) async {
    opened.add(url);

    final failure = openFailure;

    if (failure != null) {
      throw failure;
    }

    onOpened?.call(this);
  }

  Future<void> _closeSheet() async {
    closes += 1;

    final failure = closeFailure;

    if (failure != null) {
      throw failure;
    }
  }

  CheckoutWatcher _watchReturnLink(
      String returnUrl, void Function(String url) onMatch) {
    _returnUrl = returnUrl;
    _onMatch = onMatch;

    return CallbackWatcher(() => stops += 1);
  }

  CheckoutWatcher _watchDismissal(void Function() onDismissed) {
    _onDismissed = onDismissed;

    return CallbackWatcher(() => stops += 1);
  }
}
