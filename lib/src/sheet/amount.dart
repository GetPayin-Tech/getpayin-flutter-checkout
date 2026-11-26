/// Currencies whose amounts carry no decimals at all.
const Set<String> _zeroDecimal = <String>{
  'BIF',
  'CLP',
  'DJF',
  'GNF',
  'JPY',
  'KMF',
  'KRW',
  'MGA',
  'PYG',
  'RWF',
  'UGX',
  'VND',
  'VUV',
  'XAF',
  'XOF',
  'XPF',
};

/// Currencies whose amounts carry three.
const Set<String> _threeDecimal = <String>{
  'BHD',
  'IQD',
  'JOD',
  'KWD',
  'LYD',
  'OMR',
  'TND'
};

/// The symbols worth writing instead of the code.
const Map<String, String> _symbols = <String, String>{
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'EGP': 'E£',
};

/// How many decimals [currency] is written with.
int decimalsFor(String currency) {
  final code = currency.trim().toUpperCase();

  if (_zeroDecimal.contains(code)) {
    return 0;
  }

  return _threeDecimal.contains(code) ? 3 : 2;
}

/// Writes [amountMinor] the way the payer expects to see it on a pay button.
///
/// [amountMinor] is in hundredths whatever the currency, because that is how PayLink keeps
/// and charges every amount: ¥2,500 is 250000 and 25 KWD is 2500. Only the way it is written
/// follows the currency, with that currency's usual decimals. It is the amount after any
/// conversion, which is the only one worth showing: it is what will actually be charged.
/// Hundredths that a no-decimal currency cannot write are shown rather than rounded away.
/// A currency with no symbol of its own is written with its code, which is better than a
/// wrong symbol.
String formatAmount(int amountMinor, String currency) {
  final code = currency.trim().toUpperCase();
  final (scaled, decimals) = _scaled(amountMinor.abs(), decimalsFor(code));
  final sign = amountMinor < 0 ? '-' : '';
  final digits = scaled.toString().padLeft(decimals + 1, '0');
  final whole = digits.substring(0, digits.length - decimals);
  final fraction =
      decimals == 0 ? '' : '.${digits.substring(digits.length - decimals)}';
  final grouped = _group(whole);
  final symbol = _symbols[code];

  return symbol == null
      ? '$sign$grouped$fraction $code'
      : '$sign$symbol$grouped$fraction';
}

/// [hundredths] as a whole number of the smallest unit written with [decimals], and the
/// decimals it is written with.
///
/// Whole numbers only, so nothing is lost to floating point. A no-decimal amount that is not
/// a whole number keeps its two decimals.
(int, int) _scaled(int hundredths, int decimals) {
  return switch (decimals) {
    3 => (hundredths * 10, 3),
    0 when hundredths % 100 == 0 => (hundredths ~/ 100, 0),
    _ => (hundredths, 2),
  };
}

/// Puts a comma every three digits, which is what every currency here is written with.
String _group(String whole) {
  final out = StringBuffer();

  for (var index = 0; index < whole.length; index += 1) {
    if (index > 0 && (whole.length - index) % 3 == 0) {
      out.write(',');
    }

    out.write(whole[index]);
  }

  return out.toString();
}
