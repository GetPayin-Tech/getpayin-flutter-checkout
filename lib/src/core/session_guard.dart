import '../errors.dart';

/// The one checkout this process is allowed to be running.
///
/// Shared rather than owned by the facade, because the payment sheet is a checkout too: a
/// second one opened over it would stack a live web view under a dead one, and an
/// integrator gating their pay button on [GetPayInCheckout.busy] would be told nothing is
/// happening while a payer is mid-charge.
///
/// Replaceable so a test can start from a clean one, the way the deep-link watcher and the
/// browser ports are: a checkout left open by one test would otherwise refuse every
/// checkout after it.
SessionGuard checkoutGuard = SessionGuard();

/// Lets one checkout run at a time.
///
/// Two checkouts at once would stack a second web view over a live one, and the payer's
/// card details would go to whichever happened to be on top.
class SessionGuard {
  bool _active = false;

  /// True while a checkout is running.
  bool get busy => _active;

  /// Runs [work], refusing to start while another run is in flight.
  ///
  /// Throws [GetPayInSessionBusyError] when a checkout is already running.
  Future<T> run<T>(Future<T> Function() work) async {
    if (_active) {
      throw const GetPayInSessionBusyError();
    }

    _active = true;

    try {
      return await work();
    } finally {
      _active = false;
    }
  }
}
