/// Base class for every error this package throws.
///
/// It implements [Exception] rather than extending [Error]: these are conditions a
/// payment flow is expected to handle, not programming faults to crash on.
class GetPayInCheckoutError implements Exception {
  /// Creates an error carrying [message].
  const GetPayInCheckoutError(this.message);

  /// What went wrong, for a developer. Never show it to a payer.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when `open()` is called with something that is not a usable checkout URL.
class GetPayInConfigError extends GetPayInCheckoutError {
  /// Creates a configuration error carrying [message].
  const GetPayInConfigError(super.message);
}

/// Thrown when an in-app checkout is opened with no `GetPayInProvider` above it.
///
/// The two cases are told apart because the fix is different: no provider is mounted at
/// all, or one is mounted somewhere the app's `Navigator` cannot be reached from.
class GetPayInProviderMissingError extends GetPayInCheckoutError {
  /// No provider is mounted anywhere in the app.
  const GetPayInProviderMissingError()
      : super(
          'No GetPayInProvider is mounted. Wrap a widget under your app with '
          'GetPayInProvider to open the checkout in the app, or render '
          'GetPayInCheckoutView in a screen of your own.',
        );

  /// A provider is mounted, but it cannot reach a `Navigator` to present a screen on.
  const GetPayInProviderMissingError.withoutNavigator()
      : super(
          'GetPayInProvider found no Navigator to present the checkout on. Mount it '
          'below your app\'s Navigator (for example around the widget you pass to '
          'MaterialApp.home), or give it the navigatorKey you pass to MaterialApp.',
        );
}

/// Thrown when a checkout is opened while another one is still running.
class GetPayInSessionBusyError extends GetPayInCheckoutError {
  /// Creates the busy error.
  const GetPayInSessionBusyError()
      : super(
            'A checkout is already open. Wait for it to finish before opening another.');
}
