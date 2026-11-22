/// Take Apple Pay, Google Pay and card payments inside a Flutter app with the hosted
/// GetPayIn checkout.
///
/// Three things make up the public surface:
///
/// - `GetPayInCheckout.open`, which presents a checkout and completes with the outcome.
/// - [GetPayInProvider], mounted once, which hosts the in-app screen it is presented on.
/// - [GetPayInCheckoutView], for putting the checkout in a screen of your own instead.
///
/// The result is a report of what the return link said, never proof of payment. Confirm the
/// `invoice.paid` webhook on your own server before you fulfil an order.
library;

export 'src/checkout.dart' show GetPayInCheckout;
export 'src/core/messages.dart';
export 'src/core/navigation.dart'
    show NavigationContext, NavigationVerdict, classifyNavigation;
export 'src/core/presentation.dart' show resolvePresentation;
export 'src/core/return_url.dart'
    show cancelledResult, matchesReturnUrl, readCheckoutResult, resolveReturn;
export 'src/errors.dart';
export 'src/payment_return_redirect.dart' show PaymentReturnRedirect;
export 'src/types.dart';
export 'src/webview/app_schemes.dart'
    show declareHostAppSchemes, hostAppSchemes;
export 'src/webview/navigation_handler.dart'
    show CheckoutNavigationHandler, NavigationRequestInfo;
export 'src/webview/platform_settings.dart'
    show CheckoutWebViewSettings, buildCheckoutWebViewSettings;
export 'src/widgets/getpayin_checkout_view.dart'
    show CheckoutLoadErrorCallback, GetPayInCheckoutView;
export 'src/widgets/getpayin_provider.dart' show GetPayInProvider;
