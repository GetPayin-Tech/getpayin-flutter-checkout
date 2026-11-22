// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'card_fields_controller.dart';
import 'saved_card.dart';
import 'sheet_style.dart';

/// The row above everything: a close button, or a back arrow on a second screen.
class SheetHeader extends StatelessWidget {
  /// Creates the header.
  const SheetHeader({
    required this.style,
    required this.semanticLabel,
    required this.onPressed,
    this.isBack = false,
    super.key,
  });

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  /// What a screen reader announces for the button.
  final String semanticLabel;

  /// Closes the sheet, or goes back a screen.
  final VoidCallback onPressed;

  /// Draw a back arrow instead of a close cross, on the left instead of the right.
  final bool isBack;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onPressed,
      icon: Icon(isBack ? Icons.arrow_back_ios_new : Icons.close, size: 20),
      color: style.mutedText,
      tooltip: semanticLabel,
      visualDensity: VisualDensity.compact,
    );

    return Align(
      alignment: isBack ? Alignment.centerLeft : Alignment.centerRight,
      child: button,
    );
  }
}

/// A screen's title, as big as the one on the card form.
class SheetTitle extends StatelessWidget {
  /// Creates the title.
  const SheetTitle(this.text, {required this.style, super.key});

  /// The title.
  final String text;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: style.text),
      ),
    );
  }
}

/// The small grey label over a group of rows.
class SectionLabel extends StatelessWidget {
  /// Creates the label.
  const SectionLabel(this.text, {required this.style, super.key});

  /// The label.
  final String text;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 14, color: style.mutedText)),
    );
  }
}

/// The "Or pay using" rule between the wallet and the cards.
class OrDivider extends StatelessWidget {
  /// Creates the divider.
  const OrDivider({required this.label, required this.style, super.key});

  /// The words in the middle of the rule.
  final String label;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: style.border, height: 1));

    return Row(
      children: <Widget>[
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: TextStyle(fontSize: 13, color: style.mutedText)),
        ),
        line,
      ],
    );
  }
}

/// One way to pay: a bordered row that can be picked.
class MethodRow extends StatelessWidget {
  /// Creates the row.
  const MethodRow({
    required this.style,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
    super.key,
  });

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  /// The row's first line.
  final String title;

  /// What sits at the start of the row.
  final Widget? leading;

  /// The row's second line, when it has one.
  final String? subtitle;

  /// What sits at the end of the row.
  final Widget? trailing;

  /// Whether this is the way the payer has picked.
  final bool selected;

  /// Picks this row. A null callback greys it out.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: style.surface,
        borderRadius: BorderRadius.circular(style.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(style.radius),
          child: Container(
            height: style.rowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(style.radius),
              border: Border.all(
                color: selected ? style.selectedBorder : style.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: 12)
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: enabled ? style.text : style.mutedText,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: style.mutedText),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card network, written rather than drawn.
///
/// The networks' marks are trademarks with their own artwork rules, so this package ships
/// none of them: it writes the name on a neutral chip, which is honest and needs no licence.
/// Pass your own widget instead when you have the marks your acquirer approved.
class BrandMark extends StatelessWidget {
  /// Creates the mark.
  const BrandMark({required this.brand, super.key});

  /// The network to name.
  final CardBrand brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1F3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _short,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Color(0xFF30313D),
        ),
      ),
    );
  }

  String get _short => switch (brand) {
        CardBrand.visa => 'VISA',
        CardBrand.mastercard => 'MC',
        CardBrand.amex => 'AMEX',
        CardBrand.discover => 'DISC',
        CardBrand.unionPay => 'UP',
        CardBrand.mada => 'MADA',
        CardBrand.unknown => 'CARD',
      };
}

/// The tick the sheet ends on, in the accent the pay button was drawn in.
///
/// Flat, and no bigger than it needs to be: a payment going through is the expected
/// outcome, and a sheet that celebrates it reads as relief that it worked.
class PaidMark extends StatelessWidget {
  /// Creates the mark.
  const PaidMark({required this.style, super.key});

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: style.accent, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 32, color: style.accentText),
      ),
    );
  }
}

/// A tappable word in the sheet's accent colour.
class LinkText extends StatelessWidget {
  /// Creates the link.
  const LinkText(this.text,
      {required this.style, required this.onTap, super.key});

  /// The words.
  final String text;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  /// What tapping it does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(text, style: TextStyle(fontSize: 14, color: style.accent)),
          Icon(Icons.chevron_right, size: 18, color: style.accent),
        ],
      ),
    );
  }
}

/// What went wrong with this attempt, in the payer's language.
class ErrorText extends StatelessWidget {
  /// Creates the error line.
  const ErrorText(this.message, {required this.style, super.key});

  /// The message.
  final String message;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(message, style: TextStyle(fontSize: 13, color: style.danger)),
    );
  }
}

/// The button that takes the payment.
class PayButton extends StatelessWidget {
  /// Creates the button.
  const PayButton({
    required this.label,
    required this.style,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  /// What it says, amount included.
  final String label;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  /// Takes the payment. Null while there is nothing chargeable yet.
  final VoidCallback? onPressed;

  /// Whether the charge is already running.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: style.accent,
          foregroundColor: style.accentText,
          disabledBackgroundColor: style.accent.withValues(alpha: 0.4),
          disabledForegroundColor: style.accentText.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.radius),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: style.accentText,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.lock_outline, size: 15),
                ],
              ),
      ),
    );
  }
}

/// The card box: the one part of the sheet the gateway draws.
class CardBox extends StatelessWidget {
  /// Creates the box.
  const CardBox({required this.controller, required this.style, super.key});

  /// The box's own controller, which owns the page behind it.
  final CardFieldsController controller;

  /// How the sheet is drawn.
  final PaymentSheetStyle style;

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: controller.webView);
  }
}
