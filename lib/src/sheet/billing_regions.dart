/// A region the charge carries, for the two countries whose regions it carries.
///
/// PayLink reads a state for the United States and a province for Canada and drops the
/// answer everywhere else, so these are the only two lists the sheet needs. The code is
/// what travels; the name is what the payer reads.
class BillingRegion {
  /// Creates a region for the billing form.
  const BillingRegion(this.code, this.name);

  /// The two-letter code the charge carries.
  final String code;

  /// What the payer reads in the list.
  final String name;
}

/// The regions a country's billing form offers, empty where it asks for none.
List<BillingRegion> billingRegionsOf(String country) => switch (country) {
      'US' => _unitedStates,
      'CA' => _canada,
      _ => const <BillingRegion>[],
    };

const List<BillingRegion> _unitedStates = <BillingRegion>[
  BillingRegion('AL', 'Alabama'),
  BillingRegion('AK', 'Alaska'),
  BillingRegion('AS', 'American Samoa'),
  BillingRegion('AZ', 'Arizona'),
  BillingRegion('AR', 'Arkansas'),
  BillingRegion('AA', 'Armed Forces Americas'),
  BillingRegion('AE', 'Armed Forces Europe'),
  BillingRegion('AP', 'Armed Forces Pacific'),
  BillingRegion('CA', 'California'),
  BillingRegion('CO', 'Colorado'),
  BillingRegion('CT', 'Connecticut'),
  BillingRegion('DE', 'Delaware'),
  BillingRegion('DC', 'District of Columbia'),
  BillingRegion('FL', 'Florida'),
  BillingRegion('GA', 'Georgia'),
  BillingRegion('GU', 'Guam'),
  BillingRegion('HI', 'Hawaii'),
  BillingRegion('ID', 'Idaho'),
  BillingRegion('IL', 'Illinois'),
  BillingRegion('IN', 'Indiana'),
  BillingRegion('IA', 'Iowa'),
  BillingRegion('KS', 'Kansas'),
  BillingRegion('KY', 'Kentucky'),
  BillingRegion('LA', 'Louisiana'),
  BillingRegion('ME', 'Maine'),
  BillingRegion('MD', 'Maryland'),
  BillingRegion('MA', 'Massachusetts'),
  BillingRegion('MI', 'Michigan'),
  BillingRegion('MN', 'Minnesota'),
  BillingRegion('MS', 'Mississippi'),
  BillingRegion('MO', 'Missouri'),
  BillingRegion('MT', 'Montana'),
  BillingRegion('NE', 'Nebraska'),
  BillingRegion('NV', 'Nevada'),
  BillingRegion('NH', 'New Hampshire'),
  BillingRegion('NJ', 'New Jersey'),
  BillingRegion('NM', 'New Mexico'),
  BillingRegion('NY', 'New York'),
  BillingRegion('NC', 'North Carolina'),
  BillingRegion('ND', 'North Dakota'),
  BillingRegion('MP', 'Northern Mariana Islands'),
  BillingRegion('OH', 'Ohio'),
  BillingRegion('OK', 'Oklahoma'),
  BillingRegion('OR', 'Oregon'),
  BillingRegion('PA', 'Pennsylvania'),
  BillingRegion('PR', 'Puerto Rico'),
  BillingRegion('RI', 'Rhode Island'),
  BillingRegion('SC', 'South Carolina'),
  BillingRegion('SD', 'South Dakota'),
  BillingRegion('TN', 'Tennessee'),
  BillingRegion('TX', 'Texas'),
  BillingRegion('UT', 'Utah'),
  BillingRegion('VT', 'Vermont'),
  BillingRegion('VI', 'Virgin Islands'),
  BillingRegion('VA', 'Virginia'),
  BillingRegion('WA', 'Washington'),
  BillingRegion('WV', 'West Virginia'),
  BillingRegion('WI', 'Wisconsin'),
  BillingRegion('WY', 'Wyoming'),
];

const List<BillingRegion> _canada = <BillingRegion>[
  BillingRegion('AB', 'Alberta'),
  BillingRegion('BC', 'British Columbia'),
  BillingRegion('MB', 'Manitoba'),
  BillingRegion('NB', 'New Brunswick'),
  BillingRegion('NL', 'Newfoundland and Labrador'),
  BillingRegion('NT', 'Northwest Territories'),
  BillingRegion('NS', 'Nova Scotia'),
  BillingRegion('NU', 'Nunavut'),
  BillingRegion('ON', 'Ontario'),
  BillingRegion('PE', 'Prince Edward Island'),
  BillingRegion('QC', 'Quebec'),
  BillingRegion('SK', 'Saskatchewan'),
  BillingRegion('YT', 'Yukon'),
];
