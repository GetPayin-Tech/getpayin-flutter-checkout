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
}
