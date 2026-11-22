import 'package:getpayin_checkout/getpayin_checkout.dart';

/// The return link every test opens a checkout with.
const String testReturnUrl = 'myapp://payment-return';

/// The checkout URL a server would hand the app.
const String testCheckoutUrl = 'https://pay.getpayin.com/checkout/abc';

/// The return link carrying [query].
String returnLink(String query) => '$testReturnUrl?$query';

/// A request for the checkout the session tests present.
CheckoutRequest testRequest({Object? expectedInvoiceId}) {
  return CheckoutRequest(
    checkoutUrl: testCheckoutUrl,
    options: OpenCheckoutOptions(
      returnUrl: testReturnUrl,
      expectedInvoiceId: expectedInvoiceId,
    ),
  );
}

/// The page the integrator hosts at the origin registered for the integration.
const String testFieldsPageUrl = 'https://shop.example.com/paylink-fields.html';

/// The origin that page is served from.
const String testOrigin = 'https://shop.example.com';

/// What `/init` answers for a payment opened with `mode: "fields"`.
Map<String, Object?> testInitResponse({
  String origin = testOrigin,
  Object? invoiceId = 90210,
  String? expiresAt,
}) {
  return <String, Object?>{
    'success': true,
    'data': <String, Object?>{
      'checkout_url': testCheckoutUrl,
      'invoice_id': invoiceId,
      'fields': <String, Object?>{
        'client_token': 'eyJpdiI6ZXhhbXBsZQ',
        'sdk_url': 'https://pay.example.com/sdk/paylink-fields-v1.js',
        'origin': origin,
        if (expiresAt != null) 'expires_at': expiresAt,
      },
    },
  };
}

/// The session the sheet runs against.
PayLinkFieldsSession testFieldsSession({String origin = testOrigin}) {
  return PayLinkFieldsSession.fromInit(testInitResponse(origin: origin))!;
}
