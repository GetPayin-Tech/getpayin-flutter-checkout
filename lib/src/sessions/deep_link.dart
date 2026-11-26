import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../core/return_url.dart';
import '../core/url.dart';
import 'watcher.dart';

/// Where the return link can arrive from while a checkout is open.
///
/// Taken as two functions rather than the plugin itself so the ordering rules below can be
/// tested without a phone, which is the whole point of keeping them here.
class DeepLinkSource {
  /// Creates a source from an initial-link reader and a stream of later links.
  const DeepLinkSource({required this.initialLink, required this.links});

  /// Builds the source every app uses: `app_links`.
  factory DeepLinkSource.platform() {
    final appLinks = AppLinks();

    return DeepLinkSource(
      initialLink: appLinks.getInitialLink,
      links: () => appLinks.uriLinkStream,
    );
  }

  /// The link the app was launched with, read once as the app starts.
  ///
  /// It is not only the launch link: the plugin answers with the first link the *process*
  /// ever saw, whenever that arrived, so it belongs to no checkout in particular.
  final Future<Uri?> Function() initialLink;

  /// Links delivered as they happen, listened to once for the life of the app.
  final Stream<Uri> Function() links;
}

/// Watches for the return link arriving as a deep link, once per checkout.
///
/// One rule decides everything here: **a checkout is only told about links that arrive
/// while it is watching.** A link it did not wait for never settles it.
///
/// The rule is kept on this side because neither source the plugin offers is tied to a
/// live checkout. The initial link persists for the life of the process, and links that
/// arrive before anything in Dart listens are replayed to the first listener. So the
/// subscription is opened once, as the app starts, the initial link is read there and
/// nowhere else, and a link that arrives with nothing waiting for it is dropped.
///
/// It matters because an app's return scheme is public, and anything on the phone can open
/// the app with a link shaped like a return link.
class ReturnLinkWatcher {
  /// Creates a watcher over [source], or over `app_links` when none is given.
  ///
  /// [now] is the clock the watcher reads, for a test that has to move it.
  ReturnLinkWatcher({DeepLinkSource? source, DateTime Function()? now})
      : _source = source ?? DeepLinkSource.platform(),
        _now = now ?? DateTime.now;

  final DeepLinkSource _source;

  final DateTime Function() _now;

  /// The checkouts waiting for a link right now, in the order they started.
  final List<_CheckoutWatch> _watching = <_CheckoutWatch>[];

  /// Links the app received while starting, refused ever after.
  ///
  /// The launch link can reach the app by both of the plugin's paths, in either order, so
  /// the decision about it is remembered rather than taken twice.
  final Set<String> _startupLinks = <String>{};

  /// How long a link that reached no checkout, or settled one, is refused for.
  static const Duration _spentFor = Duration(minutes: 10);

  /// Links that reached the app with nobody waiting, or settled a checkout, and when.
  ///
  /// The plugin can hand a link over again: by both of its paths, or to an activity Android
  /// recreated. Such a link belongs to a checkout that is over, and offered to the next one
  /// it would settle that one on another payment's answer, so it is refused. Kept for
  /// [_spentFor] rather than for the life of the process: a repeat comes within moments,
  /// and the app's own links, which can carry anything, a sign-in token included, are not
  /// kept beyond that.
  final Map<String, DateTime> _spent = <String, DateTime>{};

  /// The one subscription, opened as the app starts and never cancelled.
  ///
  /// It belongs to the process rather than to a checkout: a link that arrives with nobody
  /// watching is dropped here, where a stream nothing listens to would hold it for the next
  /// listener instead.
  StreamSubscription<Uri>? _subscription;

  Future<void>? _priming;
  bool _primed = false;

  /// Starts listening, and takes the launch link out of circulation.
  ///
  /// Idempotent, and called by the provider as it mounts, so both happen while the app
  /// starts rather than in the middle of a payment. A checkout that opens before this has
  /// finished hears nothing until it has: a link arriving in that window belongs to no
  /// checkout either.
  Future<void> prime() => _priming ??= _begin();

  /// Starts watching for [returnUrl], calling [onMatch] at most once.
  CheckoutWatcher watch(String returnUrl, void Function(String url) onMatch) {
    final watching = _CheckoutWatch(returnUrl, onMatch);

    _watching.add(watching);
    unawaited(prime());

    return CallbackWatcher(() => _watching.remove(watching));
  }

  /// Opens the subscription and reads the launch link, in that order.
  ///
  /// Listening first is what keeps a link held for the next listener from being handed to a
  /// checkout instead.
  Future<void> _begin() async {
    _subscription ??= _source.links().listen(_arrived, onError: (Object _) {});

    await _readInitialLink(_startupLinks.add);

    _primed = true;
  }

  /// Offers one link to every checkout watching, and drops it when none is.
  ///
  /// A link dropped, or taken by a checkout, is spent: a second delivery of it is refused.
  void _arrived(Uri uri) {
    final url = uri.toString();

    if (!_primed) {
      _startupLinks.add(url);

      return;
    }

    final now = _now();

    _spent.removeWhere((_, at) => now.difference(at) >= _spentFor);

    if (_startupLinks.contains(url) || _spent.containsKey(url)) {
      _dropped(url, 'it was already handed over or dropped');

      return;
    }

    if (_watching.isEmpty) {
      _spent[url] = now;
      _dropped(url, 'no checkout was waiting for it');

      return;
    }

    var taken = false;

    for (final watching in _watching.toList(growable: false)) {
      taken = watching.offer(url) || taken;
    }

    if (taken) {
      _spent[url] = now;
    }
  }

  /// Says in a debug build that a link was dropped, and why, without what it carried: the
  /// app's own links can carry anything, a sign-in token included.
  void _dropped(String url, String why) {
    if (kDebugMode) {
      debugPrint('GetPayIn: dropped a link to ${linkForLog(url)}: $why');
    }
  }

  /// Reads the launch link and hands it to [take], swallowing a source that cannot answer.
  ///
  /// A plugin that fails here has nothing useful to report: the stream still carries every
  /// link that arrives while a checkout is open, which is the only kind that settles one.
  Future<void> _readInitialLink(void Function(String url) take) async {
    try {
      final uri = await _source.initialLink();

      if (uri != null) {
        take(uri.toString());
      }
    } catch (_) {
      return;
    }
  }
}

/// One checkout waiting for its return link.
class _CheckoutWatch {
  /// Creates the wait for [returnUrl].
  _CheckoutWatch(this.returnUrl, this.onMatch);

  /// The link this checkout ends on.
  final String returnUrl;

  /// Called with the first link that is that one.
  final void Function(String url) onMatch;

  bool _matched = false;

  /// Hands [url] over when it is the link this checkout is waiting for, once, and says
  /// whether it did.
  bool offer(String url) {
    if (_matched || !matchesReturnUrl(url, returnUrl)) {
      return false;
    }

    _matched = true;
    onMatch(url);

    return true;
  }
}

/// The watcher the browser session uses, replaced in tests.
ReturnLinkWatcher returnLinkWatcher = ReturnLinkWatcher();
