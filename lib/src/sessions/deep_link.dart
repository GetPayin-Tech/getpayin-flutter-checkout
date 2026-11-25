import 'dart:async';

import 'package:app_links/app_links.dart';

import '../core/return_url.dart';
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
  ReturnLinkWatcher({DeepLinkSource? source})
      : _source = source ?? DeepLinkSource.platform();

  final DeepLinkSource _source;

  /// The checkouts waiting for a link right now, in the order they started.
  final List<_CheckoutWatch> _watching = <_CheckoutWatch>[];

  /// Links that reached the app with nothing waiting for them, refused ever after.
  ///
  /// One link can reach the app by both of the plugin's paths, in either order, so the
  /// decision is remembered rather than taken twice. A later link identical to a dropped
  /// one is dropped with it: a checkout that hears nothing ends as cancelled, which is the
  /// answer to give when there is nothing to tie a link to the payment in front of it.
  final Set<String> _orphaned = <String>{};

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

    await _readInitialLink(_orphaned.add);

    _primed = true;
  }

  /// Offers one link to every checkout watching, and drops it when none is.
  void _arrived(Uri uri) {
    final url = uri.toString();

    if (!_primed || _watching.isEmpty || _orphaned.contains(url)) {
      _orphaned.add(url);

      return;
    }

    for (final watching in _watching.toList(growable: false)) {
      watching.offer(url);
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

  /// Hands [url] over when it is the link this checkout is waiting for, once.
  void offer(String url) {
    if (_matched || !matchesReturnUrl(url, returnUrl)) {
      return;
    }

    _matched = true;
    onMatch(url);
  }
}

/// The watcher the browser session uses, replaced in tests.
ReturnLinkWatcher returnLinkWatcher = ReturnLinkWatcher();
