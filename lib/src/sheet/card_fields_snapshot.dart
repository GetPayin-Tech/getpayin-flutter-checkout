import 'fields_protocol.dart';

/// Every field the gateway has to be holding before a card can be charged.
const Set<String> _chargeable = <String>{'number', 'securityCode', 'expiry'};

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
    this.valid = const <String>{},
  });

  /// True once the fields are live and the gateway has priced the payment.
  final bool ready;

  /// True while the issuer's 3-D Secure challenge is up.
  final bool authenticating;

  /// True once the charge is running and can no longer be called off.
  final bool charging;

  /// What will actually be charged, in minor units, once the gateway has said.
  final int? amountMinor;

  /// The currency it will be charged in, once the gateway has said.
  final String? currency;

  /// The last thing worth showing the payer about the card they entered.
  final String? errorMessage;

  /// The fields holding something chargeable, by the name the page calls them.
  final Set<String> valid;

  /// True when every field in the box holds something chargeable and the box is live.
  bool get isComplete => ready && valid.containsAll(_chargeable);

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
    Set<String>? valid,
  }) {
    return CardFieldsSnapshot(
      ready: ready ?? this.ready,
      authenticating: authenticating ?? this.authenticating,
      charging: charging ?? this.charging,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      errorMessage: errorMessage,
      valid: valid ?? this.valid,
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
      valid: valid,
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
    FieldsChanged(:final field, :final valid, :final empty) => _fieldChanged(
        snapshot,
        field: field,
        valid: valid,
        empty: empty,
      ),
    FieldsAuthenticating() => snapshot.copyWith(authenticating: true),
    FieldsCharging() => snapshot.copyWith(charging: true),
    FieldsPayment() =>
      snapshot.copyWith(charging: false, authenticating: false),
    FieldsError(:final message) => snapshot
        .copyWith(charging: false, authenticating: false)
        .withMessage(message),
    FieldsWalletReady() || FieldsWalletError() => snapshot,
  };
}

/// The box after one field changed.
///
/// A payer who is correcting a card should not still be reading why the last one was
/// refused, so typing into a field clears the message. An empty field is not a correction
/// yet, and clearing it there would take the explanation away the moment they touched the
/// form.
CardFieldsSnapshot _fieldChanged(
  CardFieldsSnapshot snapshot, {
  required String field,
  required bool valid,
  required bool empty,
}) {
  final fields = <String>{...snapshot.valid};

  valid ? fields.add(field) : fields.remove(field);

  final changed = snapshot.copyWith(valid: fields);

  return empty ? changed : changed.withMessage(null);
}
