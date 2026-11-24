/// A card the payer has already used, as your own backend remembers it.
///
/// A token never reaches the app in either direction: a card is vaulted by a payment created
/// with `tokenize: true`, your server keeps what comes back on the `card_token.created`
/// webhook, and charging one is a call your server makes with your hash token. The sheet
/// only shows what you hand it and tells you which one the payer picked.
class SavedCard {
  /// Creates a saved card.
  const SavedCard({
    required this.id,
    required this.last4,
    this.brand = CardBrand.unknown,
    this.expiryMonth,
    this.expiryYear,
    this.label,
  });

  /// Your own identifier for the vaulted card. The sheet hands it back, nothing more.
  final String id;

  /// The last four digits, which is all the payer needs to tell two cards apart.
  final String last4;

  /// The network, for the logo beside it.
  final CardBrand brand;

  /// Expiry month, when you have it, for an "expired" hint.
  final int? expiryMonth;

  /// Expiry year, when you have it.
  final int? expiryYear;

  /// Text shown instead of the brand name, for a card the payer named themselves.
  final String? label;

  /// True when the card can no longer be charged, so the sheet can grey it out.
  bool get hasExpired {
    final month = expiryMonth;
    final year = expiryYear;

    if (month == null || year == null) {
      return false;
    }

    final now = DateTime.now();
    final endOfMonth = DateTime(year, month + 1);

    return !endOfMonth.isAfter(DateTime(now.year, now.month));
  }
}

/// The card networks the sheet draws a logo for.
enum CardBrand {
  /// Visa.
  visa('Visa'),

  /// Mastercard.
  mastercard('Mastercard'),

  /// American Express.
  amex('American Express'),

  /// Discover.
  discover('Discover'),

  /// UnionPay.
  unionPay('UnionPay'),

  /// Mada.
  mada('Mada'),

  /// A network with no logo of its own here.
  unknown('Card');

  const CardBrand(this.label);

  /// What to call it in text, for a screen reader and for a card with no logo.
  final String label;

  /// The brand a gateway's name for it means, or [unknown].
  static CardBrand fromName(String? name) {
    final wanted =
        (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

    return switch (wanted) {
      'visa' => CardBrand.visa,
      'mastercard' || 'mc' || 'master' => CardBrand.mastercard,
      'amex' || 'americanexpress' => CardBrand.amex,
      'discover' => CardBrand.discover,
      'unionpay' || 'cup' => CardBrand.unionPay,
      'mada' => CardBrand.mada,
      _ => CardBrand.unknown,
    };
  }
}

/// A wallet the sheet can offer.
///
/// One per payment: a charge is booked under the first wallet its capture context offered,
/// not the one the payer picked, so PayLink refuses a context that carries two.
enum PaymentWallet {
  /// Apple Pay. Needs your origin verified with Apple before it renders.
  applePay('APPLEPAY', 'ios'),

  /// Google Pay. Available to any company that sells it.
  googlePay('GOOGLEPAY', 'android');

  const PaymentWallet(this.wireName, this.platform);

  /// What PayLink calls it.
  final String wireName;

  /// The platform it belongs on.
  final String platform;

  /// The one wallet worth offering on [platform], or null when none of [wanted] belongs.
  static PaymentWallet? forPlatform(
      String platform, List<PaymentWallet> wanted) {
    for (final wallet in wanted) {
      if (wallet.platform == platform) {
        return wallet;
      }
    }

    return null;
  }
}
