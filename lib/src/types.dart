/// The three outcomes a checkout can end in.
///
/// [paid] and [notPaid] are what the return link reported; [cancelled] means the payer
/// closed the screen or the browser sheet without finishing.
enum CheckoutStatus {
  /// The return link reported the invoice as paid in full.
  paid('paid'),

  /// The payment did not go through, or the link could not be trusted to say it did.
  notPaid('not_paid'),

  /// The payer closed the checkout without finishing.
  cancelled('cancelled');

  const CheckoutStatus(this.wireName);

  /// The value GetPayIn's own APIs and the other SDKs use, for logs and payloads.
  final String wireName;
}

/// Why a checkout was not reported as paid, when the reason is worth acting on.
///
/// [CheckoutResult.message] is text for the payer and changes with the app's language;
/// this is the stable value to branch on, and the key to look a message of your own up by.
///
/// [unreadableReturnLink] means the link's own fields could not be read: a genuine decline
/// carries no code at all, so the two are told apart by this rather than by text. It is the
/// one to alert on — it means the backend and this reader disagree about the shape of the
/// link. [wrongInvoice] means the link named another invoice. The payer may well have paid
/// in both cases, so neither is a reason to ask for payment again before the invoice has
/// been checked on your server.
enum CheckoutResultCode {
  /// The link's own fields could not be read the way the backend writes them.
  unreadableReturnLink('unreadable_return_link'),

  /// The link named an invoice other than the one this checkout was opened for.
  wrongInvoice('wrong_invoice'),

  /// The link reported an invoice state that is not paid in full.
  unexpectedInvoiceStatus('unexpected_invoice_status'),

  /// A charge started and its answer never arrived, so nobody knows how it ended.
  ///
  /// The one result that is neither a payment nor a refusal. The gateway had the charge
  /// before the answer was lost — the network went, the page died, the payer closed the
  /// sheet mid-charge — so the card may well have been charged.
  ///
  /// Do not take payment again on this code. Read the invoice on your server, and wait for
  /// the `invoice.paid` webhook, which arrives whether or not the app was still listening.
  outcomeUnknown('outcome_unknown'),

  /// The checkout could not be shown at all, so the payer never got to pay.
  ///
  /// Only the payment sheet reports this, and only with its fallback to the hosted
  /// checkout turned off: nothing was charged and nothing was declined. With the fallback
  /// on — which is the default — the payer is sent to the hosted checkout instead and this
  /// never arrives.
  checkoutUnavailable('checkout_unavailable');

  const CheckoutResultCode(this.wireName);

  /// The stable text form of the code, for logs and analytics.
  final String wireName;
}

/// Where the hosted checkout is drawn.
///
/// [inApp] is a full-screen web view inside the app, [browser] is the phone's browser
/// sheet (Chrome Custom Tabs on Android, SFSafariViewController on iOS).
enum CheckoutPresentation {
  /// The app's own screen, which is where the wallets can run.
  inApp('in-app'),

  /// The phone's browser sheet, where Google Pay needs no app approval.
  browser('browser');

  const CheckoutPresentation(this.wireName);

  /// The text form used by the other GetPayIn SDKs and in diagnostics.
  final String wireName;
}

/// What a finished checkout hands back.
///
/// This is a report of what the return link said, never proof of payment. Confirm the
/// `invoice.paid` webhook on your own server before you fulfil the order.
class CheckoutResult {
  /// Creates a result.
  const CheckoutResult({
    required this.status,
    this.invoiceId,
    this.invoiceStatus,
    this.code,
    this.message,
    this.returnUrl,
  });

  /// How the checkout ended.
  final CheckoutStatus status;

  /// The invoice the return link named, as text, when it carried one.
  final String? invoiceId;

  /// The invoice state the return link reported, as GetPayIn wrote it: `PAID`, `UNPAID`,
  /// `PARTIALLY_PAID`, `AUTHORIZED` and so on.
  ///
  /// Only `PAID` is reported as [CheckoutStatus.paid]. Anything else is
  /// [CheckoutStatus.notPaid] with [CheckoutResultCode.unexpectedInvoiceStatus], because
  /// an authorised or part-paid invoice is not an order to fulfil. Null when the link did
  /// not carry the field.
  final String? invoiceStatus;

  /// Why this is not a paid result, when the reason is worth branching on.
  final CheckoutResultCode? code;

  /// Text for the payer, in the language the checkout or this package produced it in.
  final String? message;

  /// The return link this result was read from, when there was one.
  final String? returnUrl;

  /// True when the return link reported the invoice as paid in full.
  ///
  /// Still not proof of payment: only the `invoice.paid` webhook on your server is.
  bool get isPaid => status == CheckoutStatus.paid;

  /// A copy with the outcome fields replaced, for the rules that refuse a paid result.
  ///
  /// Only the three fields a downgrade touches can be replaced. The invoice it named and
  /// the link it came from are facts about the link and are carried through unchanged.
  CheckoutResult downgradedTo(
    CheckoutStatus status, {
    required CheckoutResultCode code,
    required String message,
  }) {
    return CheckoutResult(
      status: status,
      invoiceId: invoiceId,
      invoiceStatus: invoiceStatus,
      code: code,
      message: message,
      returnUrl: returnUrl,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CheckoutResult &&
        other.status == status &&
        other.invoiceId == invoiceId &&
        other.invoiceStatus == invoiceStatus &&
        other.code == code &&
        other.message == message &&
        other.returnUrl == returnUrl;
  }

  @override
  int get hashCode =>
      Object.hash(status, invoiceId, invoiceStatus, code, message, returnUrl);

  @override
  String toString() {
    return 'CheckoutResult(status: ${status.wireName}, invoiceId: $invoiceId, '
        'invoiceStatus: $invoiceStatus, code: ${code?.wireName}, message: $message)';
  }
}

/// Options shared by every way of presenting a checkout.
class CheckoutOptions {
  /// Creates the options a checkout is presented with.
  const CheckoutOptions({
    required this.returnUrl,
    this.expectedInvoiceId,
    this.googlePayInApp = false,
    this.ownSchemes = const <String>[],
    this.presentation,
    this.loadErrorMessage,
    this.linkErrorMessage,
  });

  /// The link the checkout sends the payer back to, for example `myapp://payment-return`.
  ///
  /// It has to match the **Mobile App Return Scheme** on the GetPayIn integration.
  final String returnUrl;

  /// The invoice this checkout is for, as your server reported it alongside the
  /// `checkout_url`.
  ///
  /// Supply it whenever you have it. The return link is a public app scheme that any web
  /// page, message or other app on the phone can invoke with whatever query it likes, so a
  /// link naming a different invoice is not this checkout's result. With this set, such a
  /// link is reported as [CheckoutStatus.notPaid] instead of being taken at its word.
  ///
  /// An `int` is accepted as well as a `String`: `POST /api/integration/init` returns the
  /// invoice id as a JSON number, while the return link carries it as text. The two are
  /// compared as trimmed text, with leading zeros ignored on a digits-only id.
  ///
  /// Null means "no invoice to bind to", and turns the check off. Anything else that is
  /// not a non-blank `String` or a whole number — `''`, `true`, a `Map` such as the whole
  /// init response, a fractional or non-finite `double` — is refused with
  /// `GetPayInConfigError`, because taken as "not given" it would accept a paid link for
  /// any invoice and compared against it would report every real payment as not paid.
  ///
  /// Dart cannot tell a field your server left out of its JSON from an option you chose
  /// not to pass: both arrive as null and both turn the check off. Make sure your server
  /// always sends the invoice id.
  final Object? expectedInvoiceId;

  /// Draw the checkout in the app's own screen on Android, which only offers Google Pay
  /// after Google has approved the app.
  ///
  /// Leave it off until then, so Android payers get the browser sheet where Google Pay
  /// needs no approval. Ignored on iOS, which always uses the app's own screen.
  final bool googlePayInApp;

  /// Other URL schemes this app answers to, refused like the return link's scheme.
  ///
  /// Merged with whatever `declareHostAppSchemes` was given. A page inside the checkout
  /// must not be able to drive the host app's own deep-link routes, and Flutter has no app
  /// config to read them from, so the app is what declares them.
  final List<String> ownSchemes;

  /// Overrides the presentation rule. Intended for tests and for diagnosing a build.
  final CheckoutPresentation? presentation;

  /// The text shown to the payer when the checkout page cannot be loaded, in your app's
  /// language.
  final String? loadErrorMessage;

  /// The text shown to the payer when the phone cannot open a link the checkout needed, in
  /// your app's language.
  ///
  /// A 3-D Secure step that sends the payer to their bank's app is the case this covers: if
  /// the app is not installed, the checkout cannot go on, so the payer is told why and
  /// given the way out rather than being left on a screen whose button does nothing.
  final String? linkErrorMessage;
}

/// Options for `GetPayInCheckout.open`, which presents the checkout on its own screen.
class OpenCheckoutOptions extends CheckoutOptions {
  /// Creates the options one `open()` call is made with.
  const OpenCheckoutOptions({
    required super.returnUrl,
    super.expectedInvoiceId,
    super.googlePayInApp,
    super.ownSchemes,
    super.presentation,
    super.loadErrorMessage,
    super.linkErrorMessage,
    this.title,
    this.closeLabel,
    this.headerShown = true,
  });

  /// Title shown in the in-app screen's top bar.
  final String? title;

  /// The label of the in-app screen's close button, in your app's language.
  ///
  /// When set, it is also what a screen reader announces for the button (otherwise
  /// "Close checkout").
  final String? closeLabel;

  /// Show the in-app screen's top bar, which is the payer's only way to close the
  /// checkout.
  ///
  /// The bar is shown anyway when the checkout fails to load, so a failure always has a
  /// way out.
  final bool headerShown;
}

/// A checkout the provider has been asked to present.
class CheckoutRequest {
  /// Creates a request for one checkout.
  const CheckoutRequest({required this.checkoutUrl, required this.options});

  /// The `checkout_url` your server received from `POST /api/integration/init`.
  final String checkoutUrl;

  /// How this checkout is to be presented.
  final OpenCheckoutOptions options;
}

/// Presents a checkout and completes once it ends.
typedef CheckoutPresenter = Future<CheckoutResult> Function(
    CheckoutRequest request);
