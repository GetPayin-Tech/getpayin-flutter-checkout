import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/core/url.dart';

void main() {
  group('parseUrl', () {
    test('splits a custom app scheme', () {
      expect(
        parseUrl('myapp://payment-return?status=paid'),
        const ParsedUrl(
          scheme: 'myapp',
          authority: 'payment-return',
          path: '',
          query: 'status=paid',
        ),
      );
    });

    test('splits an https URL with a path', () {
      expect(
        parseUrl('https://pay.getpayin.com/checkout/abc?x=1#frag'),
        const ParsedUrl(
          scheme: 'https',
          authority: 'pay.getpayin.com',
          path: '/checkout/abc',
          query: 'x=1',
        ),
      );
    });

    test('handles a scheme with no authority', () {
      expect(
        parseUrl('mailto:support@example.com'),
        const ParsedUrl(
          scheme: 'mailto',
          authority: '',
          path: '/support@example.com',
          query: '',
        ),
      );
    });

    test('lowercases the scheme and host but keeps the path case', () {
      final parsed = parseUrl('HTTPS://Pay.GetPayIn.com/Checkout');

      expect(parsed?.scheme, 'https');
      expect(parsed?.authority, 'pay.getpayin.com');
      expect(parsed?.path, '/Checkout');
    });

    test('rejects a value with no scheme', () {
      expect(parseUrl('payment-return?status=paid'), isNull);
    });

    test('rejects an empty value', () {
      expect(parseUrl('   '), isNull);
    });
  });

  group('isSameTarget', () {
    test('treats a missing and a present trailing slash as one target', () {
      expect(isSameTarget('myapp://return/', 'myapp://return'), isTrue);
    });

    test('separates two hosts', () {
      expect(isSameTarget('myapp://a', 'myapp://b'), isFalse);
    });

    test('is false when either side is unparseable', () {
      expect(isSameTarget('nonsense', 'myapp://return'), isFalse);
      expect(isSameTarget('myapp://return', 'nonsense'), isFalse);
    });
  });

  group('readQuery', () {
    test('keeps names exactly as sent, in order', () {
      final params = readQuery('Invoice_Id=1&invoice_id=2&success=1');

      expect(params.keys.toList(),
          <String>['Invoice_Id', 'invoice_id', 'success']);
      expect(params, <String, List<String>>{
        'Invoice_Id': <String>['1'],
        'invoice_id': <String>['2'],
        'success': <String>['1'],
      });
    });

    test('keeps every value of a repeated name, in order', () {
      expect(readQuery('success=1&success=0')['success'], <String>['1', '0']);
    });

    test('decodes names and values, with a plus as a space', () {
      expect(readQuery('invoice%5Fid=7')['invoice_id'], <String>['7']);
      expect(readQuery('message=Card+declined%21')['message'],
          <String>['Card declined!']);
    });

    test('keeps a parameter with no value', () {
      expect(readQuery('flag')['flag'], <String>['']);
    });

    test('keeps an equals sign inside a value', () {
      expect(readQuery('token=a=b')['token'], <String>['a=b']);
    });

    test('skips empty pairs', () {
      expect(readQuery('&&a=1'), <String, List<String>>{
        'a': <String>['1'],
      });
    });

    test('returns nothing for an empty query', () {
      expect(readQuery(''), isEmpty);
    });
  });

  group('rawQueryNames', () {
    test('reports names before any decoding, in order', () {
      expect(
        rawQueryNames('%73uccess=1&invoice_id=7'),
        <String>['%73uccess', 'invoice_id'],
      );
    });
  });

  group('decodeQueryComponent', () {
    test('leaves a malformed escape sequence alone rather than throwing', () {
      expect(decodeQueryComponent('100%25%ZZ'), '100%25%ZZ');
    });
  });

  group('normalizeToken', () {
    test('strips case, spacing and separators', () {
      expect(normalizeToken('  Not_Paid '), 'notpaid');
      expect(normalizeToken('user-cancelled'), 'usercancelled');
    });
  });

  group('normalizeScheme', () {
    test('drops the separator an app config writes a scheme with', () {
      expect(normalizeScheme('MyApp://'), 'myapp');
      expect(normalizeScheme(' third: '), 'third');
    });

    test('keeps separators inside the scheme, which are part of it', () {
      expect(normalizeScheme('MyApp-iOS'), 'myapp-ios');
    });

    test('reduces a value that is nothing but a separator to nothing', () {
      expect(normalizeScheme('://'), '');
    });
  });
}
