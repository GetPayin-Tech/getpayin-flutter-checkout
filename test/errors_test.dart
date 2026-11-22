import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

void main() {
  group('the error types', () {
    test('all share one base, so one catch covers them', () {
      expect(const GetPayInConfigError('bad'), isA<GetPayInCheckoutError>());
      expect(
          const GetPayInProviderMissingError(), isA<GetPayInCheckoutError>());
      expect(const GetPayInSessionBusyError(), isA<GetPayInCheckoutError>());
    });

    test('name themselves in their text, so a log says which one it was', () {
      expect(const GetPayInConfigError('bad').toString(),
          contains('GetPayInConfigError'));
      expect(const GetPayInConfigError('bad').toString(), contains('bad'));
    });

    test('tell a developer what to do about a missing provider', () {
      expect(
        const GetPayInProviderMissingError().message,
        contains('GetPayInProvider'),
      );
      expect(
        const GetPayInProviderMissingError.withoutNavigator().message,
        contains('navigatorKey'),
      );
    });
  });
}
