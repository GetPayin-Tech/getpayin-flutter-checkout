import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_flutter_checkout/src/core/deferred.dart';

void main() {
  group('Deferred', () {
    test('settles with the first value and reports that it has', () async {
      final deferred = Deferred<String>();

      expect(deferred.settled, isFalse);
      deferred.resolve('first');

      expect(deferred.settled, isTrue);
      expect(await deferred.future, 'first');
    });

    /*
     * The return link can reach the app from more than one source at once, and a second
     * settle would be a second result for one checkout — where a bare Completer throws.
     */
    test('ignores every settle after the first', () async {
      final deferred = Deferred<String>()
        ..resolve('first')
        ..resolve('second')
        ..reject(StateError('too late'));

      expect(await deferred.future, 'first');
    });

    test('can settle with a failure instead', () async {
      final deferred = Deferred<String>()..reject(StateError('no browser'));

      expect(deferred.settled, isTrue);
      await expectLater(deferred.future, throwsStateError);
    });
  });
}
