import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/sessions/deep_link.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

/*
 * A checkout is only ever told about links that arrive while it is watching. Neither source
 * `app_links` offers is tied to a live checkout: the initial link answers with the first
 * link the process ever saw, whenever that arrived, and links that arrive before Dart
 * listens are replayed to whoever listens first. So the watcher opens its one subscription
 * as the app starts, reads the initial link there, and drops anything that arrives with
 * nothing waiting for it.
 *
 * Every test here drives both sources the way the plugin drives them.
 */

void main() {
  late FakeDeepLinks links;

  setUp(() => links = FakeDeepLinks());
  tearDown(() => links.dispose());

  group('the link the app was launched with', () {
    test('never settles a checkout opened later in the same process', () async {
      links.launchedWith(returnLink('success=1&invoice_id=INV-ELSEWHERE'));

      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      expect(matched, isEmpty);
      watching.stop();
    });

    test('is refused however late the stream pushes it', () async {
      final launch = returnLink('success=1&invoice_id=INV-ELSEWHERE');

      links.launchedWith(launch);

      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();
      links.emit(launch);
      await flush();

      expect(matched, isEmpty);
      watching.stop();
    });

    test(
        'does not block a genuine link that arrives while the checkout is open',
        () async {
      links.launchedWith(returnLink('success=1&invoice_id=INV-ELSEWHERE'));

      final watcher = ReturnLinkWatcher(source: links.source);
      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      final genuine = returnLink('success=1&invoice_id=INV-REAL');

      links.emit(genuine);
      await flush();

      expect(matched, <String>[genuine]);
      watching.stop();
    });

    test('reads the launch link once however many checkouts run', () async {
      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await watcher.prime();

      final watching = watcher.watch(testReturnUrl, (_) {});

      await flush();
      watching.stop();

      expect(links.initialReads, 1);
    });
  });

  group('a link nobody is waiting for', () {
    test('does not settle the checkout that comes after it', () async {
      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      final declined = returnLink('success=0&invoice_id=INV-FIRST');
      final first = <String>[];
      final firstWatch = watcher.watch(testReturnUrl, first.add);

      await flush();
      links.emit(declined);
      await flush();
      firstWatch.stop();

      final second = <String>[];
      final secondWatch = watcher.watch(testReturnUrl, second.add);

      await flush();

      expect(first, <String>[declined]);
      expect(second, isEmpty);
      secondWatch.stop();
    });

    test('is dropped when it arrives between two checkouts', () async {
      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      links.emit(returnLink('success=1&invoice_id=INV-STRAY'));
      await flush();

      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      expect(matched, isEmpty);
      watching.stop();
    });
  });

  group('the deep-link watcher', () {
    test('reports a repeated link once per checkout, not once per process',
        () async {
      final watcher = ReturnLinkWatcher(source: links.source);
      final url = returnLink('success=1&invoice_id=INV-REAL');

      final first = <String>[];
      final firstWatch = watcher.watch(testReturnUrl, first.add);

      await flush();
      links.emit(url);
      links.emit(url);
      await flush();
      firstWatch.stop();

      final second = <String>[];
      final secondWatch = watcher.watch(testReturnUrl, second.add);

      await flush();
      links.emit(url);
      await flush();
      secondWatch.stop();

      expect(first, hasLength(1));
      expect(second, hasLength(1));
    });

    test('ignores a link that is not the return link', () async {
      final watcher = ReturnLinkWatcher(source: links.source);
      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();
      links.emit('myapp://something-else?success=1');
      links.emit('https://pay.getpayin.com/checkout/abc');
      await flush();

      expect(matched, isEmpty);
      watching.stop();
    });

    test('hears nothing more once it has stopped', () async {
      final watcher = ReturnLinkWatcher(source: links.source);
      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();
      watching.stop();
      await flush();
      links.emit(returnLink('success=1'));
      await flush();

      expect(matched, isEmpty);
      expect(
        links.listening,
        isTrue,
        reason: 'the one subscription is the process-long one, not a checkout',
      );
    });

    test('carries on when the link stream reports an error', () async {
      final watcher = ReturnLinkWatcher(source: links.source);
      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();
      links.fail(StateError('the platform channel went away'));
      await flush();

      final genuine = returnLink('success=1');

      links.emit(genuine);
      await flush();

      expect(matched, <String>[genuine]);
      watching.stop();
    });

    test('carries on when the deep-link source cannot answer at all', () async {
      final watcher = ReturnLinkWatcher(
        source: DeepLinkSource(
          initialLink: () async => throw StateError('no plugin'),
          links: () => links.source.links(),
        ),
      );
      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      final genuine = returnLink('success=1');

      links.emit(genuine);
      await flush();

      expect(matched, <String>[genuine]);
      watching.stop();
    });
  });
}
