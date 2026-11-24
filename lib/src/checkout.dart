import 'card_save.dart';
import 'core/presentation.dart';
import 'core/session_guard.dart';
import 'core/validate.dart';
import 'errors.dart';
import 'platform.dart';
import 'sessions/browser_session.dart';
import 'sessions/registry.dart';
import 'types.dart';

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

    return checkoutGuard.run(
      () => presentation == CheckoutPresentation.inApp
          ? _runInAppCheckout(request)
          : runBrowserCheckout(request),
    );
  }

  /// Opens a hosted card tokenization and completes once the payer has finished.
  ///
  /// Pass the `tokenization_url` your server received from
  /// `POST /v2/integration/tokens/init`. It is a hosted run like any other — the payer
  /// enters the card on PayLink's own page, where one unit of currency is authorized to
  /// prove the card is live, the card is vaulted, and the authorization is released — so it
  /// is presented exactly as a checkout is, and everything `open` refuses, this refuses.
  ///
  /// It is read differently, though. A verification leaves its invoice unpaid on purpose,
  /// and the payment rules would call that a failure, so the result says whether the **card
  /// was saved** rather than whether an invoice was paid.
  ///
  /// The token is not in the result and never reaches the app: it arrives on your server
  /// with the `card_token.created` webhook, which is also what makes the save real.
  ///
  /// `options.expectedInvoiceId` is the verification's own invoice, which
  /// [invoiceIdInCheckoutUrl] reads off the `tokenization_url` when your server did not pass
  /// it on. Give the screen a title of its own: the payer is saving a card, not paying.
  ///
  /// Hosted card fields cannot do this, so there is no payment-sheet equivalent: a save is
  /// always a hosted run.
  static Future<CardSaveResult> saveCard(
    String tokenizationUrl,
    OpenCheckoutOptions options,
  ) async {
    final checkout = await open(tokenizationUrl, options);

    return cardSaveFromCheckout(
      checkout,
      expectedInvoiceId: options.expectedInvoiceId,
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

  /// True while a checkout is open, the payment sheet included.
  ///
  /// One guard covers both, because a second checkout opened over a live one would stack a
  /// web view under a dead one. Guard your Pay button with it to avoid
  /// [GetPayInSessionBusyError] on a double tap.
  static bool get busy => checkoutGuard.busy;
}
