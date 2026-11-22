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
/// The gateway prices a payment in minor units after any conversion, which is the only
/// amount worth showing: it is what will actually be charged. A currency with no symbol of
/// its own is written with its code, which is better than a wrong symbol.
String formatAmount(int amountMinor, String currency) {
  final code = currency.trim().toUpperCase();
  final decimals = decimalsFor(code);
  final sign = amountMinor < 0 ? '-' : '';
  final digits = amountMinor.abs().toString().padLeft(decimals + 1, '0');
  final whole = digits.substring(0, digits.length - decimals);
  final fraction =
      decimals == 0 ? '' : '.${digits.substring(digits.length - decimals)}';
  final grouped = _group(whole);
  final symbol = _symbols[code];

  return symbol == null
      ? '$sign$grouped$fraction $code'
      : '$sign$symbol$grouped$fraction';
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
