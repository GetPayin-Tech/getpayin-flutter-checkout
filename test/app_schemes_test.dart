import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/webview/app_schemes.dart';

void main() {
  tearDown(() => declareHostAppSchemes(const <String>[]));

  group('declareHostAppSchemes', () {
    test(
        'keeps every scheme the app answers to, lowercased and without repeats',
        () {
      declareHostAppSchemes(
          const <String>['MyApp', 'myapp-ios', 'com.Shop.App', 'myapp']);

      expect(
        hostAppSchemes(),
        <String>['myapp', 'myapp-ios', 'com.shop.app'],
      );
    });

    test('reads a scheme written with its separator, as a manifest tends to',
        () {
      declareHostAppSchemes(const <String>['other://', 'third:']);

      expect(hostAppSchemes(), <String>['other', 'third']);
    });

    test('skips blank entries and ones that are nothing but a separator', () {
      declareHostAppSchemes(const <String>['myapp', ' ', '://', '']);

      expect(hostAppSchemes(), <String>['myapp']);
    });

    test('is empty until the app declares anything', () {
      expect(hostAppSchemes(), isEmpty);
    });
  });

  group('normalizeSchemes', () {
    test('drops entries that are not text, as untyped configuration carries',
        () {
      expect(
        normalizeSchemes(<Object?>['first', 7, null, 'second']),
        <String>['first', 'second'],
      );
    });
  });

  group('resolveOwnSchemes', () {
    test('merges the per-checkout schemes with the declared ones', () {
      declareHostAppSchemes(const <String>['myapp']);

      expect(
        resolveOwnSchemes(const <String>['Shopdeep://', 'myapp']),
        <String>['myapp', 'shopdeep'],
      );
    });

    test('hands back the declared schemes when a checkout adds none', () {
      declareHostAppSchemes(const <String>['myapp']);

      expect(resolveOwnSchemes(), <String>['myapp']);
      expect(resolveOwnSchemes(const <String>[]), <String>['myapp']);
    });
  });
}
