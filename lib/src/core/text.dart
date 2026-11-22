/// The caller's text, or [fallback] when there is none worth showing.
///
/// Blank text counts as absent rather than being kept. `closeLabel: t('checkout.close')`
/// with a translation key that is missing yields `''`, and `?? fallback` would keep it — a
/// close button with no label and nothing for a screen reader to announce, on a full-screen
/// screen that has no back gesture on iOS. That is the payer's only way out of the
/// checkout, so an empty label would leave `open()` pending and the session guard busy for
/// the rest of the process.
String fallbackText(String? value, String fallback) {
  return value == null || value.trim().isEmpty ? fallback : value;
}
