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

/// The two deep-link sources, modelled on what `app_links` itself does.
///
/// One path covers every link, because the plugin has one: the first link a process ever
/// sees becomes the initial link and keeps being answered as such however late it arrived,
/// and a link that arrives before Dart listens is queued and replayed to whoever listens
/// first. A fake that smoothed either of them over would be standing in for an easier
/// plugin than the one that ships.
class FakeDeepLinks {
  /// Creates a source nothing has reached yet.
  FakeDeepLinks() {
    _links = StreamController<Uri>.broadcast(onListen: _replay);
  }

  late final StreamController<Uri> _links;

  /// Links held until Dart first listens, as the plugin holds them. Null once replayed.
  List<String>? _queued = <String>[];

  String? _initial;

  /// How many times the initial link has been read.
  int initialReads = 0;

  /// The link the app was launched with, as the plugin would answer it.
  String? get initial => _initial;

  /// Whether anything is listening to the link stream.
  bool get listening => _links.hasListener;

  /// The source to hand a [ReturnLinkWatcher].
  DeepLinkSource get source => DeepLinkSource(
        initialLink: () async {
          initialReads += 1;

          final url = _initial;

          return url == null ? null : Uri.parse(url);
        },
        links: () => _links.stream,
      );

  /// Opens the app with [url], before anything in Dart is listening for one.
  void launchedWith(String url) => _arrive(url);

  /// Delivers a link the way the system does while the app is running.
  void emit(String url) => _arrive(url);

  /// Reports a failure on the link stream, as a plugin that loses its channel does.
  void fail(Object error) => _links.addError(error);

  /// Closes the stream, for a test that is done with it.
  Future<void> dispose() => _links.close();

  /// One link arriving, by the plugin's own rules.
  void _arrive(String url) {
    _initial ??= url;

    if (_links.hasListener) {
      _links.add(Uri.parse(url));

      return;
    }

    _queued?.add(url);
  }

  /// Hands everything that arrived before Dart listened to the first listener.
  void _replay() {
    final queued = _queued;

    _queued = null;

    for (final url in queued ?? const <String>[]) {
      _links.add(Uri.parse(url));
    }
  }
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
