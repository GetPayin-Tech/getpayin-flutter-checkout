import 'package:flutter/widgets.dart';

/// How the payment sheet is drawn, on both sides of the web view boundary.
///
/// The card box is rendered by the page and everything around it by Flutter, so the two
/// have to agree on the same few values or the seam shows. They are defined once here and
/// handed to the page as CSS custom properties.
class PaymentSheetStyle {
  /// Creates a style.
  const PaymentSheetStyle({
    this.background = const Color(0xFFFFFFFF),
    this.surface = const Color(0xFFFFFFFF),
    this.border = const Color(0xFFE6E6E6),
    this.selectedBorder = const Color(0xFF0570DE),
    this.text = const Color(0xFF30313D),
    this.mutedText = const Color(0xFF6D6E78),
    this.placeholder = const Color(0xFFA3ACB9),
    this.danger = const Color(0xFFDF1B41),
    this.accent = const Color(0xFF0570DE),
    this.accentText = const Color(0xFFFFFFFF),
    this.radius = 8,
    this.rowHeight = 56,
  });

  /// The sheet's own background.
  final Color background;

  /// The background of a row or a box on the sheet.
  final Color surface;

  /// The line around an unselected row.
  final Color border;

  /// The line around the row the payer picked.
  final Color selectedBorder;

  /// Ordinary text.
  final Color text;

  /// Secondary text: section labels, the second line of a row.
  final Color mutedText;

  /// Placeholder text inside an input.
  final Color placeholder;

  /// Error text and an invalid field's border.
  final Color danger;

  /// The pay button and the selected row's accent.
  final Color accent;

  /// Text on the pay button.
  final Color accentText;

  /// The corner radius shared by rows, boxes and the pay button.
  final double radius;

  /// The height of a payment-method row.
  final double rowHeight;

  /// The values the page needs, as CSS custom properties.
  Map<String, Object?> toCssVariables() {
    return <String, Object?>{
      'border': _css(border),
      'danger': _css(danger),
      'placeholder': _css(placeholder),
      'text': _css(text),
      'surface': _css(surface),
      'radius': '${radius}px',
      'rowHeight': '${rowHeight}px',
    };
  }

  static String _css(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;

    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }
}
