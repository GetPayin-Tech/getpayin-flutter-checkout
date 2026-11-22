/// The address a card is billed to, as the payer typed it.
///
/// The gateway renders the card number and the security code and nothing else, so the token
/// it mints carries no address at all. Without this the charge goes out against the
/// placeholder address configured on the company, and that is what the issuer's address
/// check is matched against — for a payer who is sitting right there able to answer.
///
/// Held as one value rather than six fields on the sheet because it travels as one: the
/// same address goes on the 3-D Secure enrolment and on the charge, and the two disagreeing
/// is a refusal from the directory server after the payer has already answered their bank.
class BillingDetails {
  /// Creates a billing address. Every part is optional; [toWire] says what survives.
  const BillingDetails({
    this.name,
    this.country,
    this.state,
    this.city,
    this.address,
    this.postalCode,
  });

  /// The cardholder's name, as printed on the card.
  final String? name;

  /// The billing country, as an ISO 3166-1 alpha-2 code.
  final String? country;

  /// The state, province or region, for the countries that have one.
  final String? state;

  /// The city or town.
  final String? city;

  /// The street address.
  final String? address;

  /// The postal or ZIP code.
  final String? postalCode;

  /// True once there is enough here to be worth charging against.
  ///
  /// A street and a name that splits in two. The gateway drops an address with one name on
  /// it, and an address check with no street to check is only a postal code.
  bool get isComplete => _names() != null && _trimmed(address) != null;

  /// This address under the names PayLink's SDK reads it by.
  ///
  /// Empty when the name is not two names: the charge ignores a block without both, so
  /// sending half of one would put an address on the wire that no authorization ever sees.
  /// Everything else is left out when the payer left it out, so the company's own fallbacks
  /// still apply field by field.
  Map<String, Object?> toWire() {
    final names = _names();

    if (names == null) {
      return const <String, Object?>{};
    }

    final (firstName, lastName) = names;

    return <String, Object?>{
      'firstName': firstName,
      'lastName': lastName,
      if (_trimmed(country) case final value?) 'country': value.toUpperCase(),
      if (_trimmed(state) case final value?) 'state': value,
      if (_trimmed(city) case final value?) 'city': value,
      if (_trimmed(address) case final value?) 'address': value,
      if (_trimmed(postalCode) case final value?) 'postalCode': value,
    };
  }

  /// The name split the way the gateway wants it, or null when it will not split.
  ///
  /// Everything after the first word is the surname, which is the reading that keeps
  /// "Ada King Lovelace" intact rather than dropping a name the card carries.
  (String, String)? _names() {
    final parts = (name ?? '').trim().split(RegExp(r'\s+'))
      ..removeWhere((part) => part.isEmpty);

    if (parts.length < 2) {
      return null;
    }

    return (parts.first, parts.skip(1).join(' '));
  }

  static String? _trimmed(String? value) {
    final trimmed = value?.trim() ?? '';

    return trimmed.isEmpty ? null : trimmed;
  }
}
