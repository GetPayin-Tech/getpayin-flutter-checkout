// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'billing_countries.dart';
import 'billing_details.dart';
import 'sheet_strings.dart';
import 'sheet_style.dart';

/// What the billing form is holding, and the only thing that outlives a rebuild.
///
/// Separate from the form that draws it: the sheet needs the answers when the payer taps
/// pay, long after the widget that collected them has been rebuilt, and a form that owned
/// them would lose them every time the keyboard moved.
class BillingFieldSet {
  /// Creates an empty set, starting on [country].
  BillingFieldSet({this.country = 'EG'});

  final TextEditingController _address = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _state = TextEditingController();
  final TextEditingController _postalCode = TextEditingController();

  /// The country the payer is billed in, as an ISO 3166-1 alpha-2 code.
  String country;

  /// True where this country's region is one the charge carries.
  bool get hasRegion => billingRegionCountries.contains(country);

  /// The address as the payer has it so far, billed to [name].
  ///
  /// The name comes from the card box rather than from here, because it is one of the
  /// card's own rows; it is the half of this address the gateway cannot do without.
  BillingDetails detailsFor(String? name) {
    return BillingDetails(
      name: name,
      country: country,
      state: hasRegion ? _state.text : null,
      city: _city.text,
      address: _address.text,
      postalCode: _postalCode.text,
    );
  }

  /// Releases the fields. The sheet calls this when it closes.
  void dispose() {
    _address.dispose();
    _city.dispose();
    _state.dispose();
    _postalCode.dispose();
  }
}

/// The billing address, drawn as one box of rows the way a card form is.
///
/// Flutter rather than the hosted page, because none of it is cardholder data and a payer
/// typing an address wants their own keyboard, their own autofill and their own language.
class BillingForm extends StatelessWidget {
  /// Creates the form over [fields].
  const BillingForm({
    required this.fields,
    required this.style,
    required this.strings,
    required this.countries,
    required this.onChanged,
    super.key,
  });

  /// What the form reads and writes.
  final BillingFieldSet fields;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  /// Every word it says.
  final PaymentSheetStrings strings;

  /// The countries the payer may choose from.
  final List<BillingCountry> countries;

  /// Called whenever an answer changes, so the sheet can re-read whether it can charge.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _country(context),
      _row(fields._address, strings.addressLine, TextInputType.streetAddress),
      _row(fields._city, strings.city, TextInputType.text),
      if (fields.hasRegion)
        _row(fields._state, _regionLabel, TextInputType.text),
      _row(fields._postalCode, _postalLabel, TextInputType.text),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.surface,
        border: Border.all(color: style.border),
        borderRadius: BorderRadius.circular(style.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (index, row) in rows.indexed) ...<Widget>[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: style.border),
            row,
          ],
        ],
      ),
    );
  }

  /// What this country calls its region, so a Canadian is not asked for a state.
  String get _regionLabel =>
      fields.country == 'CA' ? strings.province : strings.state;

  /// What it calls its postal code, for the same reason.
  String get _postalLabel =>
      fields.country == 'US' ? strings.zip : strings.postalCode;

  Widget _row(
    TextEditingController controller,
    String label,
    TextInputType keyboard,
  ) {
    return SizedBox(
      height: style.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: TextField(
            controller: controller,
            keyboardType: keyboard,
            onChanged: (_) => onChanged(),
            style: TextStyle(fontSize: 16, color: style.text),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: label,
              hintStyle: TextStyle(fontSize: 16, color: style.placeholder),
            ),
          ),
        ),
      ),
    );
  }

  /// The country row, which names itself above its answer the way a card form does.
  Widget _country(BuildContext context) {
    return SizedBox(
      height: style.rowHeight + 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.country,
              style: TextStyle(fontSize: 12, color: style.mutedText),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: fields.country,
                isExpanded: true,
                isDense: true,
                iconEnabledColor: style.mutedText,
                dropdownColor: style.surface,
                style: TextStyle(fontSize: 16, color: style.text),
                onChanged: (chosen) {
                  if (chosen == null) {
                    return;
                  }

                  fields.country = chosen;
                  onChanged();
                },
                items: <DropdownMenuItem<String>>[
                  for (final country in countries)
                    DropdownMenuItem<String>(
                      value: country.code,
                      child:
                          Text(country.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
