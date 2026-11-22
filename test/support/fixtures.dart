import 'package:getpayin_flutter_checkout/getpayin_flutter_checkout.dart';

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
