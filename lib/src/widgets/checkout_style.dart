import 'package:flutter/widgets.dart';

/// The chrome around the hosted checkout, in one place.
///
/// Deliberately not read from the app's `ThemeData`: the page inside the web view is
/// GetPayIn's and is white, and a dark app theme would otherwise draw a dark bar and a dark
/// error pane around a white page. The payer sees one surface either way.
abstract final class CheckoutStyle {
  /// The surface the checkout page sits on, which matches the page itself.
  static const Color background = Color(0xFFFFFFFF);

  /// The hairline under the top bar.
  static const Color divider = Color(0xFFE2E2E6);

  /// The top bar's title.
  static const Color titleText = Color(0xFF111114);

  /// The close button's label.
  static const Color actionText = Color(0xFF0A67FF);

  /// Body text, used by the failure pane.
  static const Color bodyText = Color(0xFF5C5C63);

  /// The top bar's height, matching Material's own toolbar so it sits where a payer
  /// expects an app bar to be.
  static const double headerHeight = 56;

  /// The title's style.
  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: titleText,
  );

  /// The close button's style.
  static const TextStyle action = TextStyle(fontSize: 16, color: actionText);

  /// The failure pane's style.
  static const TextStyle body =
      TextStyle(fontSize: 15, height: 1.45, color: bodyText);
}
