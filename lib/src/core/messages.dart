/// Every default text this package can show a payer, in one place.
///
/// Each one is overridable per checkout, so an app in another language replaces it rather
/// than translating it here. They live together because the same sentence is otherwise
/// written twice — once where the in-app screen gives up and once where the browser sheet
/// does — and two copies of a payer-facing sentence drift apart.
library;

/// Shown when the checkout page itself cannot be loaded.
const String defaultLoadErrorMessage =
    'The checkout could not be loaded. Check the connection and try again.';

/// Shown when the phone cannot open a link the checkout needed, such as a bank app for a
/// 3-D Secure step that is not installed.
const String defaultLinkErrorMessage =
    'The checkout needed another app on this phone, which could not be opened. Nothing has '
    'been charged.';

/// The in-app screen's title when the caller gives none.
const String defaultCheckoutTitle = 'Secure checkout';

/// The in-app screen's close button label when the caller gives none.
const String defaultCloseLabel = 'Close';

/// What a screen reader announces for the close button when the caller gives no label.
const String defaultCloseAccessibilityLabel = 'Close checkout';

/// The reason carried by a checkout the payer closed, in either presentation.
const String closedByPayerMessage = 'The payer closed the checkout.';

/// The reason carried by a checkout cut short because its provider went away.
const String closedByUnmountMessage =
    'The checkout closed because the provider was disposed.';
