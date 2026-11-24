import '../core/url.dart';

/// Why hosted card fields could not take this payment.
///
/// Straight from PayLink's hosted-fields contract. The six marked
/// [sendsPayerToHostedCheckout] are the ones where the fields cannot run at all and the
/// payer has to be sent to `checkout_url`; everything else is about one attempt and the
/// payer can try again on the same form.
enum FieldsFailure {
  /// Hosted fields are off for this company, or the gateway refused a capture context.
  fieldsUnavailable('fields_unavailable', fatal: true),

  /// This payment is a card save, a subscription or an installment plan.
  fieldsUnsupported('fields_unsupported', fatal: true),

  /// The client token expired (60 minutes) or was never valid.
  sessionInvalid('session_invalid', fatal: true),

  /// The page is not served from the integration's registered origin.
  originNotAllowed('origin_not_allowed', fatal: true),

  /// The integration itself has been switched off in the GetPayIn dashboard.
  ///
  /// Nothing about the page, the payment or the card: the account's own setting. A payer
  /// cannot type their way past it and neither can a retry.
  integrationInactive('integration_inactive', fatal: true),

  /// The payment the client token names is gone, or was never there.
  paymentNotFound('payment_not_found', fatal: true),

  /// The card field library could not load: a content blocker, or a CSP that forbids it.
  libraryUnavailable('library_unavailable', fatal: true),

  /// Card payments for this merchant are temporarily refused by failed-payment velocity.
  paymentsPaused('payments_paused', fatal: true),

  /// The card the payer entered is not usable.
  cardInvalid('card_invalid'),

  /// The expiry the payer entered is not usable.
  expiryInvalid('expiry_invalid'),

  /// 3-D Secure came back as not authenticated.
  authenticationFailed('authentication_failed'),

  /// The payer cancelled the 3-D Secure challenge, or it timed out.
  authenticationAbandoned('authentication_abandoned'),

  /// The fields were mounted twice on one instance.
  alreadyMounted('already_mounted'),

  /// A charge for this payment is already running.
  inProgress('in_progress'),

  /// Something this package does not recognise, treated as fatal.
  unknown('unknown', fatal: true);

  const FieldsFailure(this.wireName, {this.fatal = false});

  /// The `code` PayLink reports.
  final String wireName;

  /// Whether the fields cannot run at all for this payment.
  final bool fatal;

  /// True when the only way left to take this payment is the hosted checkout.
  bool get sendsPayerToHostedCheckout => fatal;

  /// The failure [code] names, or [unknown] when it names none of them.
  ///
  /// Unknown is deliberately fatal: a code this package has not heard of is a code whose
  /// consequences it cannot reason about, and the hosted checkout always works.
  static FieldsFailure fromCode(String? code) {
    if (code == null) {
      return FieldsFailure.unknown;
    }

    final wanted = code.trim().toLowerCase();

    for (final failure in FieldsFailure.values) {
      if (failure.wireName == wanted) {
        return failure;
      }
    }

    return FieldsFailure.unknown;
  }
}

/// One payment, as `POST /v2/integration/init` with `mode: "fields"` described it.
///
/// Your server makes that call — it is signed with your hash token, which must never reach
/// the app — and passes this block on. Everything here is safe on a device: the client token
/// is encrypted, lasts 60 minutes, names exactly one payment, and cannot create, refund or
/// read anything.
class PayLinkFieldsSession {
  /// Creates a session from the parts `/init` returned.
  const PayLinkFieldsSession({
    required this.clientToken,
    required this.sdkUrl,
    required this.origin,
    required this.checkoutUrl,
    this.invoiceId,
    this.expiresAt,
  });

  /// Reads the session out of what `/init` answered.
  ///
  /// Takes either the whole envelope or its `data` block, because a server that forwards
  /// "the payment" to its app sends one or the other and neither is wrong. Null when the
  /// response carries no `fields` block at all, which is what a company without hosted
  /// fields gets: the caller falls back to [checkoutUrl].
  static PayLinkFieldsSession? fromInit(Map<String, Object?> response) {
    final data = _mapAt(response, 'data') ?? response;
    final fields = _mapAt(data, 'fields');
    final checkoutUrl =
        _stringAt(data, 'checkout_url') ?? _stringAt(data, 'checkoutUrl');

    if (fields == null || checkoutUrl == null) {
      return null;
    }

    final clientToken =
        _stringAt(fields, 'client_token') ?? _stringAt(fields, 'clientToken');
    final sdkUrl = _stringAt(fields, 'sdk_url') ?? _stringAt(fields, 'sdkUrl');
    final origin = _stringAt(fields, 'origin');

    if (clientToken == null || sdkUrl == null || origin == null) {
      return null;
    }

    return PayLinkFieldsSession(
      clientToken: clientToken,
      sdkUrl: sdkUrl,
      origin: origin,
      checkoutUrl: checkoutUrl,
      invoiceId: _scalarAt(data, 'invoice_id') ?? _scalarAt(data, 'invoiceId'),
      expiresAt: DateTime.tryParse(
        _stringAt(fields, 'expires_at') ?? _stringAt(data, 'expires_at') ?? '',
      ),
    );
  }

  /// Authorises the fields calls. Carried as a bearer token, never in a URL.
  final String clientToken;

  /// Where PayLink serves the fields SDK the page loads.
  final String sdkUrl;

  /// The origin registered on the integration, which the fields page must be served from.
  final String origin;

  /// The hosted checkout, which is the fallback for everything the fields cannot do.
  final String checkoutUrl;

  /// The invoice this payment is for, as `/init` reported it.
  final Object? invoiceId;

  /// When the client token stops working.
  final DateTime? expiresAt;

  /// True once the client token can no longer be used, so the caller can mint a new one.
  bool get hasExpired {
    final expiry = expiresAt;

    return expiry != null && !expiry.isAfter(DateTime.now().toUtc());
  }

  /// True when [pageUrl] is served from the origin this session was issued for.
  ///
  /// The origin is baked into the capture context CyberSource issues and checked on every
  /// call, so a page served from anywhere else renders no fields at all. Checking it here
  /// turns that silence into an error the integrator can read.
  bool servesFrom(String pageUrl) {
    final page = parseUrl(pageUrl);
    final registered = parseUrl(origin);

    if (page == null || registered == null) {
      return false;
    }

    return page.scheme == registered.scheme &&
        page.authority == registered.authority;
  }
}

Map<String, Object?>? _mapAt(Map<String, Object?> source, String key) {
  final value = source[key];

  return value is Map<String, Object?> ? value : null;
}

String? _stringAt(Map<String, Object?> source, String key) {
  final value = source[key];

  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

Object? _scalarAt(Map<String, Object?> source, String key) {
  final value = source[key];

  return value is String || value is num ? value : null;
}
