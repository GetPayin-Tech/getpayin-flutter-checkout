// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getpayin_checkout/getpayin_checkout.dart';

/*
 * The charge carries a region for two countries and drops it everywhere else, so the form
 * asks for one only where it will be used — and calls it what that country calls it, since
 * a Canadian asked for a state has been handed someone else's form.
 */
void main() {
  const countries = <BillingCountry>[
    BillingCountry('EG', 'Egypt'),
    BillingCountry('US', 'United States'),
    BillingCountry('CA', 'Canada'),
  ];

  late BillingFieldSet fields;
  late int changes;

  setUp(() => changes = 0);
  tearDown(() => fields.dispose());

  /// Pumps the form over a fresh field set, rebuilt on change the way the sheet does it.
  ///
  /// The form draws what the fields hold and decides nothing for itself, so a host that
  /// does not rebuild would never show the region row appearing.
  Future<void> pumpForm(WidgetTester tester, {String country = 'EG'}) async {
    fields = BillingFieldSet(country: country);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BillingForm(
              fields: fields,
              style: const PaymentSheetStyle(),
              strings: const PaymentSheetStrings(),
              countries: countries,
              onChanged: () => setState(() => changes++),
            ),
          ),
        ),
      ),
    );
  }

  group('the billing form', () {
    const strings = PaymentSheetStrings();

    testWidgets('starts on the first region rather than on nothing',
        (tester) async {
      await pumpForm(tester, country: 'US');

      expect(find.text('Alabama'), findsOneWidget);
      expect(
        fields.detailsFor('Ada Lovelace').toWire()['state'],
        'AL',
        reason:
            'a picker always has an answer, so the charge always carries one',
      );
    });

    testWidgets('asks for no region where the charge carries none',
        (tester) async {
      await pumpForm(tester);

      expect(find.text(strings.state), findsNothing);
      expect(find.text(strings.province), findsNothing);
      expect(find.text(strings.postalCode), findsOneWidget);
    });

    testWidgets('asks an American for a state and a ZIP', (tester) async {
      await pumpForm(tester, country: 'US');

      expect(find.text(strings.state), findsOneWidget);
      expect(find.text(strings.zip), findsOneWidget);
      expect(find.text(strings.postalCode), findsNothing);
    });

    testWidgets('asks a Canadian for a province', (tester) async {
      await pumpForm(tester, country: 'CA');

      expect(find.text(strings.province), findsOneWidget);
      expect(find.text(strings.state), findsNothing);
      expect(find.text(strings.postalCode), findsOneWidget);
    });

    testWidgets('changes country, and the form with it', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('Egypt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canada').last);
      await tester.pumpAndSettle();

      expect(fields.country, 'CA');
      expect(changes, 1);
      expect(find.text(strings.province), findsOneWidget);
    });

    testWidgets('carries the region only where it is asked for',
        (tester) async {
      await pumpForm(tester, country: 'US');

      await tester.tap(find.text('Alabama'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alaska').last);
      await tester.pumpAndSettle();

      final billed = fields.detailsFor('Ada Lovelace').toWire();

      expect(billed['state'], 'AK');

      fields.country = 'EG';

      expect(fields.detailsFor('Ada Lovelace').toWire()['state'], isNull);
    });
  });
}
