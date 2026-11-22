// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'billing_countries.dart';
import 'billing_details.dart';
import 'billing_regions.dart';
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
  final TextEditingController _postalCode = TextEditingController();

  /// The region the payer chose, for a country that has a list of them.
  String? region;

  /// The country the payer is billed in, as an ISO 3166-1 alpha-2 code.
  String country;

  /// True where this country's region is one the charge carries.
  bool get hasRegion => billingRegionsOf(country).isNotEmpty;

  /// The address as the payer has it so far, billed to [name].
  ///
  /// The name comes from the card box rather than from here, because it is one of the
  /// card's own rows; it is the half of this address the gateway cannot do without.
  BillingDetails detailsFor(String? name) {
    return BillingDetails(
      name: name,
      country: country,
      state:
          hasRegion ? (region ?? billingRegionsOf(country).first.code) : null,
      city: _city.text,
      address: _address.text,
      postalCode: _postalCode.text,
    );
  }

  /// Releases the fields. The sheet calls this when it closes.
  void dispose() {
    _address.dispose();
    _city.dispose();
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
    final regions = billingRegionsOf(fields.country);
    final rows = <Widget>[
      _picker(
        label: strings.country,
        value: fields.country,
        options: <(String, String)>[
          for (final country in countries) (country.code, country.name),
        ],
        onChosen: (chosen) => fields.country = chosen,
      ),
      _row(fields._address, strings.addressLine, TextInputType.streetAddress),
      _row(fields._city, strings.city, TextInputType.text),
      if (regions.isNotEmpty)
        _picker(
          label: _regionLabel,
          value: fields.region ?? regions.first.code,
          options: <(String, String)>[
            for (final region in regions) (region.code, region.name),
          ],
          onChosen: (chosen) => fields.region = chosen,
        ),
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

  /// A row the payer chooses from rather than types into.
  ///
  /// Named above its answer rather than beside it, because a chosen value is already there
  /// to read and a placeholder would have nowhere to go once it was.
  Widget _picker({
    required String label,
    required String value,
    required List<(String, String)> options,
    required void Function(String chosen) onChosen,
  }) {
    return SizedBox(
      height: style.rowHeight + 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: 12, color: style.mutedText)),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                iconEnabledColor: style.mutedText,
                dropdownColor: style.surface,
                style: TextStyle(fontSize: 16, color: style.text),
                onChanged: (chosen) {
                  if (chosen == null) {
                    return;
                  }

                  onChosen(chosen);
                  onChanged();
                },
                items: <DropdownMenuItem<String>>[
                  for (final (code, name) in options)
                    DropdownMenuItem<String>(
                      value: code,
                      child: Text(name, overflow: TextOverflow.ellipsis),
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
