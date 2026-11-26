import '../core/deferred.dart';
import '../core/messages.dart';
import '../core/return_url.dart';
import '../types.dart';

/// The lifecycle of the one checkout a provider is showing, with no widget behind it.
///
/// [onChange] is called with the checkout to show, and with null once it ends, which is
/// what a provider turns into a screen being pushed and popped.
class CheckoutSessionHost {
  /// Creates a host that reports what to show through [onChange].
  CheckoutSessionHost(this.onChange);

  /// Called with the checkout to show, then with null when it ends.
  final void Function(CheckoutRequest? request) onChange;

  CheckoutRequest? _request;
  Deferred<CheckoutResult>? _pending;
  CheckoutResult? _unconfirmed;

  /// The checkout being shown, or null when there is none.
  CheckoutRequest? get current => _request;

  /// Presents a checkout and completes once it ends.
  Future<CheckoutResult> present(CheckoutRequest request) {
    final pending = Deferred<CheckoutResult>();

    _request = request;
    _pending = pending;
    _unconfirmed = null;
    onChange(request);

    return pending.future;
  }

  /// From now on, the open checkout settles as [result] if it goes without an answer.
  ///
  /// A failure after the checkout page had loaded may have followed a charge. A checkout
  /// that goes after that, by the payer's close, the app's own code or the provider going,
  /// is one nobody can confirm, never a cancelled one. An answer still settles it as sent.
  void holdUnconfirmed(CheckoutResult result) {
    if (_pending != null) {
      _unconfirmed = result;
    }
  }

  /// Settles the open checkout with [result].
  ///
  /// Does nothing when nothing is open, so a result arriving after the payer closed the
  /// screen — or a second copy of the same one — cannot report a payment twice.
  void finish(CheckoutResult result) {
    final pending = _pending;

    if (pending == null) {
      return;
    }

    _pending = null;
    _request = null;
    _unconfirmed = null;
    pending.resolve(result);
    onChange(null);
  }

  /// Settles the open checkout as cancelled, or as unconfirmed once [holdUnconfirmed] has
  /// said so.
  void cancel([String? message]) {
    finish(_unconfirmed ?? cancelledResult(message ?? closedByPayerMessage));
  }

  /// Settles anything still open, for a provider that is going away.
  void dispose() {
    cancel(closedByUnmountMessage);
  }
}
