import 'billing_details.dart';
import 'fields_protocol.dart';

/// Every field the gateway has to be holding before a card can be charged.
const Set<String> _chargeable = <String>{'number', 'securityCode', 'expiry'};

/// The row the gateway writes itself, where the payer agrees to the card being kept.
const String consentField = 'consent';

/// What the card box knows about itself, at one moment.
///
/// Separate from the controller that drives the page, because what the box *is* and what it
/// *talks to* change for different reasons: this moves when the payer types, and the
/// controller moves when the web view does. Keeping them apart is what lets every rule
/// below be tested with no page, no channel and no widget.
class CardFieldsSnapshot {
  /// Creates a snapshot. The default is a box that has not mounted yet.
  const CardFieldsSnapshot({
    this.ready = false,
    this.authenticating = false,
    this.charging = false,
    this.amountMinor,
    this.currency,
    this.errorMessage,
    this.cardholderName,
    this.chargeStarted = false,
    this.valid = const <String>{},
    this.consentHeight = 0,
  });

  /// True once the fields are live and the gateway has priced the payment.
  final bool ready;

  /// True while the issuer's 3-D Secure challenge is up.
  final bool authenticating;

  /// True once the charge is running and can no longer be called off.
  final bool charging;

  /// What will actually be charged, in hundredths whatever the currency, once the gateway
  /// has said.
  final int? amountMinor;

  /// The currency it will be charged in, once the gateway has said.
  final String? currency;

  /// The last thing worth showing the payer about the card they entered.
  final String? errorMessage;

  /// True from the moment the gateway is handed this attempt's charge until it answers.
  ///
  /// What the sheet needs to know when something goes wrong is not whether an attempt is
  /// running but whether the charge itself left: after it did, no failure can honestly be
  /// reported as nothing having been charged. Asking the issuer comes first and charges
  /// nothing, so 3-D Secure does not set it, and a failed or abandoned challenge stays a step
  /// the payer can retry. A payment of either kind is an answer and clears it; a failure does
  /// not, because the answer is what it lost.
  final bool chargeStarted;

  /// The name the payer typed on the card, which the charge is billed to.
  ///
  /// Typed into the card box rather than beside it, because the box's rows have to line up
  /// and the gateway draws two of them. It is not cardholder data in the sense the number
  /// and the security code are, so the page may hand it over and the sheet may hold it.
  final String? cardholderName;

  /// The fields holding something chargeable, by the name the page calls them.
  final Set<String> valid;

  /// How tall the consent row is on the page, once it has said.
  ///
  /// Zero until then, and zero for a box without one. Every other row is the height the
  /// sheet asked for; this one is PayLink's own, and its wording wraps in some languages.
  final int consentHeight;

  /// True when every field in the box holds something chargeable and the box is live.
  bool get isComplete => ready && valid.containsAll(_chargeable);

  /// True once the payer has agreed to the card being kept.
  ///
  /// Asked separately from [isComplete] because a sheet that is not keeping the card has no
  /// such row, and one that is cannot charge without it.
  bool get hasConsent => valid.contains(consentField);

  /// A copy with the parts a single event can move replaced.
  ///
  /// [errorMessage] is not among them: a message is set and cleared deliberately, through
  /// [withMessage], rather than by whichever caller happened to omit it.
  CardFieldsSnapshot copyWith({
    bool? ready,
    bool? authenticating,
    bool? charging,
    int? amountMinor,
    String? currency,
    String? cardholderName,
    bool? chargeStarted,
    Set<String>? valid,
    int? consentHeight,
  }) {
    return CardFieldsSnapshot(
      ready: ready ?? this.ready,
      authenticating: authenticating ?? this.authenticating,
      charging: charging ?? this.charging,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      errorMessage: errorMessage,
      cardholderName: cardholderName ?? this.cardholderName,
      chargeStarted: chargeStarted ?? this.chargeStarted,
      valid: valid ?? this.valid,
      consentHeight: consentHeight ?? this.consentHeight,
    );
  }

  /// A copy carrying [message], or none when it is null.
  CardFieldsSnapshot withMessage(String? message) {
    return CardFieldsSnapshot(
      ready: ready,
      authenticating: authenticating,
      charging: charging,
      amountMinor: amountMinor,
      currency: currency,
      errorMessage: message,
      cardholderName: cardholderName,
      chargeStarted: chargeStarted,
      valid: valid,
      consentHeight: consentHeight,
    );
  }
}

/// The state a box in [snapshot] is left in by [event].
///
/// Pure, and the only place that decides what an event means to the box. An event that says
/// nothing about this box hands the same snapshot back, which is how the controller knows
/// there is nothing to tell its listeners about.
CardFieldsSnapshot applyFieldsEvent(
  CardFieldsSnapshot snapshot,
  FieldsEvent event,
) {
  return switch (event) {
    FieldsReady(:final amountMinor, :final currency) => snapshot.copyWith(
        ready: true,
        amountMinor: amountMinor,
        currency: currency,
      ),
    FieldsChanged(:final field, :final valid, :final empty, :final value) =>
      _fieldChanged(
        snapshot,
        field: field,
        valid: valid,
        empty: empty,
        value: value,
      ),
    FieldsAuthenticating(:final isChallenge) =>
      snapshot.copyWith(authenticating: isChallenge, charging: true),
    FieldsCharging() => snapshot.copyWith(charging: true, chargeStarted: true),
    FieldsPayment() => snapshot.copyWith(
        charging: false,
        authenticating: false,
        chargeStarted: false,
      ),
    FieldsError(:final message) => snapshot
        .copyWith(charging: false, authenticating: false)
        .withMessage(message),
    FieldsConsentHeight(:final pixels) =>
      snapshot.copyWith(consentHeight: pixels),
    FieldsWalletReady() || FieldsWalletError() => snapshot,
  };
}

/// The box after one field changed.
///
/// A payer who is correcting a card should not still be reading why the last one was
/// refused, so typing into a field clears the message. An empty field is not a correction
/// yet, and clearing it there would take the explanation away the moment they touched the
/// form.
///
/// A name that arrives with no value is a name the payer cleared, so it becomes empty text
/// rather than nothing: nothing keeps the old one, which would still be billed.
CardFieldsSnapshot _fieldChanged(
  CardFieldsSnapshot snapshot, {
  required String field,
  required bool valid,
  required bool empty,
  String? value,
}) {
  final name = field == _nameField ? (value?.trim() ?? '') : null;
  final fields = <String>{...snapshot.valid};

  (field == _nameField ? _isAName(name) : valid)
      ? fields.add(field)
      : fields.remove(field);

  final changed = snapshot.copyWith(valid: fields, cardholderName: name);

  return empty ? changed : changed.withMessage(null);
}

/// The one field in the box the page does not have the gateway render.
const String _nameField = 'name';

/// Whether [name] is a name the charge can be billed to.
///
/// The gateway wants a first name and a surname and ignores a billing address carrying
/// anything less, so a single word is not yet an answer. Asked through [BillingDetails] so
/// the box and the address agree on what a name is.
bool _isAName(String? name) => BillingDetails(name: name).toWire().isNotEmpty;
