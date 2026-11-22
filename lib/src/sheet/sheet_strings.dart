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
    this.nameOnCard = 'Name on card',
    this.cardNumber = 'Card number',
    this.expiry = 'MM / YY',
    this.securityCode = 'CVC',
    this.billingAddress = 'Billing address',
    this.paymentComplete = 'Payment complete',
    this.processing = 'Processing your payment',
    this.country = 'Country or region',
    this.addressLine = 'Address',
    this.city = 'City',
    this.state = 'State',
    this.province = 'Province',
    this.postalCode = 'Postal code',
    this.zip = 'ZIP',
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

  /// The placeholder in the card box's own name row.
  final String nameOnCard;

  /// The placeholder in the card number field, which the gateway renders.
  final String cardNumber;

  /// The placeholder in the expiry field.
  final String expiry;

  /// The placeholder in the security code field, which the gateway renders.
  final String securityCode;

  /// The label over the billing address.
  final String billingAddress;

  /// What the sheet says once the payment has gone through.
  final String paymentComplete;

  /// What it says while the charge is running and there is nothing to answer.
  final String processing;

  /// The label on the country list.
  final String country;

  /// The placeholder for the street address.
  final String addressLine;

  /// The placeholder for the city or town.
  final String city;

  /// What a region is called in the United States.
  final String state;

  /// What a region is called in Canada.
  final String province;

  /// What a postal code is called outside the United States.
  final String postalCode;

  /// What a postal code is called in the United States.
  final String zip;

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
