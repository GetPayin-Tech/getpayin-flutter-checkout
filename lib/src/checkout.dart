import 'core/presentation.dart';
import 'core/session_guard.dart';
import 'core/validate.dart';
import 'errors.dart';
import 'platform.dart';
import 'sessions/browser_session.dart';
import 'sessions/registry.dart';
import 'types.dart';

final SessionGuard _guard = SessionGuard();

/// Hands the request to the mounted provider.
Future<CheckoutResult> _runInAppCheckout(CheckoutRequest request) {
  final presenter = getPresenter();

  if (presenter == null) {
    throw const GetPayInProviderMissingError();
  }

  return presenter(request);
}

/// Opens the hosted GetPayIn checkout and waits for the payer to finish.
///
/// Pass the `checkout_url` your server received from `POST /api/integration/init`. Nothing
/// here signs anything and the package never sees your hash token, so the URL has to arrive
/// already signed from your own server.
abstract final class GetPayInCheckout {
  /// Presents [checkoutUrl] and completes once the checkout ends.
  ///
  /// The result reports what the return link said. It is not proof of payment — anyone can
  /// open an app with a made-up return link — so confirm the `invoice.paid` webhook on your
  /// server before you deliver the order.
  ///
  /// Every failure arrives as a failed future, including a bad [checkoutUrl], so one
  /// `catch` covers them all:
  ///
  /// - [GetPayInConfigError] when [checkoutUrl] or `options.returnUrl` is unusable, or
  ///   `options.expectedInvoiceId` is given but cannot be an invoice id.
  /// - [GetPayInProviderMissingError] when an in-app checkout has no provider mounted, or
  ///   the mounted one cannot reach a navigator.
  /// - [GetPayInSessionBusyError] when another checkout is still open.
  static Future<CheckoutResult> open(
    String checkoutUrl,
    OpenCheckoutOptions options,
  ) async {
    assertExpectedInvoiceId(options.expectedInvoiceId);
    assertReturnUrl(options.returnUrl);

    final request = CheckoutRequest(
      checkoutUrl: assertCheckoutUrl(checkoutUrl),
      options: options,
    );
    final presentation = presentationFor(
      googlePayInApp: options.googlePayInApp,
      override: options.presentation,
    );

    return _guard.run(
      () => presentation == CheckoutPresentation.inApp
          ? _runInAppCheckout(request)
          : runBrowserCheckout(request),
    );
  }

  /// Where these options would draw the checkout on this phone.
  ///
  /// Useful for a diagnostic screen that has to show whether a build will offer Google Pay
  /// in the app or in the browser sheet.
  static CheckoutPresentation presentationFor({
    bool googlePayInApp = false,
    CheckoutPresentation? override,
  }) {
    return resolvePresentation(
      platform: currentPlatformName(),
      googlePayInApp: googlePayInApp,
      override: override,
    );
  }

  /// True while a checkout is open.
  ///
  /// Guard your Pay button with it to avoid [GetPayInSessionBusyError] on a double tap.
  static bool get busy => _guard.busy;
}
