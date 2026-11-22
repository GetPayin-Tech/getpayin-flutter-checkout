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

  /// The link the activity's current intent holds, which keeps answering the same value.
  final Future<Uri?> Function() initialLink;

  /// Links delivered as they happen. Must be a broadcast stream: every checkout listens.
  final Stream<Uri> Function() links;
}

/// Watches for the return link arriving as a deep link, once per checkout.
///
/// Both sources are covered, and the asymmetry between them is the point:
///
/// - The **link stream** is a push. The system delivers each link once, as it happens, so a
///   watcher only has to ignore a second copy of its own.
/// - The **initial link** is a pull of state that persists. It keeps returning the same link
///   for as long as the activity's intent holds it, so values from it are consumed once per
///   process, and the link the app was *launched* with is consumed before any checkout can
///   start. It belongs to no session — a cold start has destroyed the future that was
///   waiting for a result — so letting a later checkout read it would report a payment that
///   never happened.
///
/// That matters because the return scheme is public: any web page, message or other app on
/// the phone can cold-start the app with a forged `?success=1&invoice_id=…`.
class ReturnLinkWatcher {
  /// Creates a watcher over [source], or over `app_links` when none is given.
  ReturnLinkWatcher({DeepLinkSource? source})
      : _source = source ?? DeepLinkSource.platform();

  final DeepLinkSource _source;

  /// Links already taken from the initial-link reader, which must be read at most once
  /// each. It grows only by distinct launch and recreated-activity intents, of which a
  /// process sees a handful.
  final Set<String> _consumed = <String>{};

  Future<void>? _launchRead;

  /// Takes the link the app was launched with out of circulation.
  ///
  /// Idempotent, and awaited by every watcher before it reads the initial link, so the
  /// ordering holds however early or late the first checkout starts. The provider also
  /// calls it as it mounts, so the launch link is consumed while the app starts rather than
  /// in the middle of a payment.
  Future<void> prime() => _launchRead ??= _readInitialLink(_consumed.add);

  /// Starts watching for [returnUrl], calling [onMatch] at most once.
  CheckoutWatcher watch(String returnUrl, void Function(String url) onMatch) {
    var stopped = false;
    var matched = false;

    void handle(String? url) {
      if (stopped ||
          matched ||
          url == null ||
          !matchesReturnUrl(url, returnUrl)) {
        return;
      }

      matched = true;
      onMatch(url);
    }

    final subscription = _source.links().listen(
          (uri) => handle(uri.toString()),
          onError: (Object _) {},
        );

    unawaited(_readIntentLink(handle));

    return CallbackWatcher(() {
      stopped = true;
      unawaited(subscription.cancel());
    });
  }

  /// Reads the activity's current intent link, which on Android carries the returning link
  /// when the system recreated the activity under a live session.
  Future<void> _readIntentLink(void Function(String url) handle) async {
    await prime();
    await _readInitialLink((url) {
      if (_consumed.add(url)) {
        handle(url);
      }
    });
  }

  /// Reads the initial link and hands it to [take], swallowing a source that cannot answer.
  ///
  /// A plugin that fails here has nothing useful to report: the other source still covers a
  /// link that arrives while the checkout is open.
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

/// The watcher the browser session uses, replaced in tests.
ReturnLinkWatcher returnLinkWatcher = ReturnLinkWatcher();
