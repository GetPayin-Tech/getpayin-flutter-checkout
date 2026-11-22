/// Every word the payment sheet shows a payer, so an app in another language replaces them.
class PaymentSheetStrings {
  /// Creates the sheet's wording.
  const PaymentSheetStrings({
    this.orPayUsing = 'Or pay using',
    this.saved = 'Saved',
    this.newPaymentMethod = 'New payment method',
    this.newCard = 'New card',
    this.viewMore = 'View more',
    this.selectCard = 'Select card',
    this.addNewCard = 'Add new card',
    this.cardInformation = 'Card information',
    this.close = 'Close',
    this.back = 'Back',
    this.pay = 'Pay',
    this.expired = 'Expired',
    this.cardDeclined = 'The payment did not go through. Try another card.',
    this.unavailable =
        'This payment cannot be taken here. Continuing in the checkout.',
  });

  /// The divider above the card list.
  final String orPayUsing;

  /// The heading over the payer's vaulted cards.
  final String saved;

  /// The heading over the ways to pay that are not saved.
  final String newPaymentMethod;

  /// The row that opens the card form.
  final String newCard;

  /// The link to the full list of saved cards.
  final String viewMore;

  /// The title of the saved-card list.
  final String selectCard;

  /// The title of the card form.
  final String addNewCard;

  /// The label over the card box.
  final String cardInformation;

  /// What a screen reader announces for the close button.
  final String close;

  /// What a screen reader announces for the back button.
  final String back;

  /// The pay button, which is followed by the amount.
  final String pay;

  /// Shown beside a saved card that can no longer be charged.
  final String expired;

  /// Shown when a charge came back refused with nothing more to say.
  final String cardDeclined;

  /// Shown while the sheet hands a payment the fields cannot take to the checkout.
  final String unavailable;
}
