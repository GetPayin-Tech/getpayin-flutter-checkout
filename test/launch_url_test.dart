import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/sessions/deep_link.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

/*
 * The app's return scheme is public: any web page, message or other app on the phone can
 * invoke it. A link planted that way cold-starts the app, and the initial-link reader keeps
 * returning it for the life of the process. If a later checkout were allowed to read it,
 * the package would report that checkout as paid, with an invoice id the attacker chose.
 *
 * Each test builds its own watcher, so the launch link is read at the point the test has
 * arranged it, which is what happens on a real launch.
 */

void main() {
  late FakeDeepLinks links;

  setUp(() => links = FakeDeepLinks());
  tearDown(() => links.dispose());

  group('the link the app was launched with', () {
    test('never settles a checkout opened later in the same process', () async {
      links.initial = returnLink('success=1&invoice_id=INV-ATTACKER');

      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      expect(matched, isEmpty);
      watching.stop();
    });

    test(
        'does not block a genuine link that arrives while the checkout is open',
        () async {
      links.initial = returnLink('success=1&invoice_id=INV-ATTACKER');

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

    test('accepts an intent link that differs from the launch link', () async {
      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await flush();

      final recreated = returnLink('success=1&invoice_id=INV-REAL');

      links.initial = recreated;

      final matched = <String>[];
      final watching = watcher.watch(testReturnUrl, matched.add);

      await flush();

      expect(matched, <String>[recreated]);
      watching.stop();
    });

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
  });

  group('the deep-link watcher', () {
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
      expect(links.listeners, 0);
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

    test('reads the launch link once however many checkouts run', () async {
      final watcher = ReturnLinkWatcher(source: links.source);

      await watcher.prime();
      await watcher.prime();

      expect(links.initialReads, 1);
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
