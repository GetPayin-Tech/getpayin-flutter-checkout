import '../types.dart';

CheckoutPresenter? _current;

/// Registers the mounted provider as the one that draws in-app checkouts.
void registerPresenter(CheckoutPresenter presenter) {
  _current = presenter;
}

/// Clears [presenter], if it is still the registered one.
///
/// Checking identity matters while a new provider is mounting over an old one: the new one
/// registers before the old one is disposed, and clearing unconditionally would leave no
/// presenter at all.
void unregisterPresenter(CheckoutPresenter presenter) {
  if (_current == presenter) {
    _current = null;
  }
}

/// The mounted provider's presenter, or null when no provider is mounted.
CheckoutPresenter? getPresenter() => _current;
