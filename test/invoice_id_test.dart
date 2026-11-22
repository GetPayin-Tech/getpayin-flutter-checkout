import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/src/core/invoice_id.dart';

/// One id and what it reduces to, so each case is one line instead of two lists.
typedef IdCase = ({String label, Object value, String expected});

void main() {
  group('normalizeInvoiceId', () {
    const cases = <(String, String)>[
      ('4512', '4512'),
      (' 4512 ', '4512'),
      ('004512', '4512'),
      ('0', '0'),
      ('000', '0'),
      (' INV-1 ', 'INV-1'),
      ('', ''),
      /*
       * `+` decodes to a space, so this is what `invoice_id=+4512` arrives as. Before it
       * was trimmed, a paid checkout was reported as not paid and the payer was offered a
       * retry.
       */
      (' 4512', '4512'),
    ];

    for (final (value, expected) in cases) {
      test('reduces "$value" to "$expected"', () {
        expect(normalizeInvoiceId(value), expected);
      });
    }
  });

  group('invoiceIdFrom', () {
    const accepted = <IdCase>[
      (label: 'the number the server reported', value: 4512, expected: '4512'),
      (label: 'zero', value: 0, expected: '0'),
      (label: 'a negative id', value: -1, expected: '-1'),
      (label: 'the same id as text', value: '4512', expected: '4512'),
      (label: 'text with whitespace', value: '  4512  ', expected: '4512'),
      (label: 'an id that is not digits', value: 'INV-1', expected: 'INV-1'),
      (
        label: 'a whole number that arrived as a double',
        value: 4512.0,
        expected: '4512'
      ),
    ];

    for (final one in accepted) {
      test('reads ${one.label} as ${one.expected}', () {
        expect(invoiceIdFrom(one.value), one.expected);
      });
    }

    const refused = <(String, Object?)>[
      ('nothing', null),
      ('an empty string', ''),
      ('a blank string', '   '),
      ('NaN', double.nan),
      ('infinity', double.infinity),
      ('true', true),
      ('the whole init response', <String, Object>{'invoice_id': 4512}),
      ('a list', <int>[4512]),
      ('a number that is not whole', 45.12),
      ('a double past the point it holds every digit', 1e21),
    ];

    for (final (label, value) in refused) {
      test('refuses $label', () {
        expect(invoiceIdFrom(value), isNull);
      });
    }
  });
}
