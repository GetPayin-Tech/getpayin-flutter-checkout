import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';
import 'package:getpayin_checkout/src/core/session_guard.dart';

void main() {
  group('SessionGuard', () {
    test('runs one checkout and frees the slot', () async {
      final guard = SessionGuard();

      expect(guard.busy, isFalse);
      expect(await guard.run(() async => 'done'), 'done');
      expect(guard.busy, isFalse);
    });

    test('refuses a second checkout while one is open', () async {
      final guard = SessionGuard();
      final first = Completer<String>();
      final running = guard.run(() => first.future);

      expect(guard.busy, isTrue);
      await expectLater(
        guard.run(() async => 'second'),
        throwsA(isA<GetPayInSessionBusyError>()),
      );

      first.complete('first');
      expect(await running, 'first');
      expect(guard.busy, isFalse);
    });

    test('frees the slot after a failed checkout', () async {
      final guard = SessionGuard();

      await expectLater(
        guard.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(guard.busy, isFalse);
    });
  });

  /*
   * The payment sheet holds the guard while it is open, and a saved card's charge runs on
   * the merchant's own server, which can answer with an issuer challenge the app has to
   * open as a checkout of its own. That one checkout is lent the sheet's place; nothing
   * else is.
   */
  group('SessionGuard.lend', () {
    test('lets the checkout it lends its place to run', () async {
      final guard = SessionGuard();
      final sheet = Completer<void>();
      final open = guard.run(() => sheet.future);

      expect(
        await guard.lend(() => guard.run(() async => 'challenge')),
        'challenge',
      );
      expect(guard.busy, isTrue, reason: 'the sheet is still open');

      sheet.complete();
      await open;
      expect(guard.busy, isFalse);
    });

    test('lends its place to one checkout at a time', () async {
      final guard = SessionGuard();
      final sheet = Completer<void>();
      final challenge = Completer<String>();
      final open = guard.run(() => sheet.future);

      await guard.lend(() async {
        final first = guard.run(() => challenge.future);

        await expectLater(
          guard.run(() async => 'second'),
          throwsA(isA<GetPayInSessionBusyError>()),
        );

        challenge.complete('first');
        expect(await first, 'first');
      });

      sheet.complete();
      await open;
    });

    test('still refuses a checkout opened from anywhere else', () async {
      final guard = SessionGuard();
      final sheet = Completer<void>();
      final charge = Completer<void>();
      final open = guard.run(() => sheet.future);
      final lent = guard.lend(() => charge.future);

      await expectLater(
        guard.run(() async => 'elsewhere'),
        throwsA(isA<GetPayInSessionBusyError>()),
      );

      charge.complete();
      sheet.complete();
      await lent;
      await open;
    });

    test('lends nothing once the work it was lent to has finished', () async {
      final guard = SessionGuard();
      final sheet = Completer<void>();
      final open = guard.run(() => sheet.future);
      late Future<String> Function() later;

      await guard.lend(() async {
        later = Zone.current.bindCallback(
          () => guard.run(() async => 'late'),
        );
      });

      await expectLater(
        later(),
        throwsA(isA<GetPayInSessionBusyError>()),
        reason:
            'a timer set up during the charge must not open a checkout later',
      );

      sheet.complete();
      await open;
    });

    test('lends nothing to another guard', () async {
      final mine = SessionGuard();
      final theirs = SessionGuard();
      final sheet = Completer<void>();
      final other = Completer<void>();
      final open = mine.run(() => sheet.future);
      final busy = theirs.run(() => other.future);

      await expectLater(
        mine.lend(() => theirs.run(() async => 'challenge')),
        throwsA(isA<GetPayInSessionBusyError>()),
      );

      sheet.complete();
      other.complete();
      await open;
      await busy;
    });
  });
}
