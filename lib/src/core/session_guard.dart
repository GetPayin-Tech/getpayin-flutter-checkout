import 'dart:async';

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
  /// The checkout running now, or null. Each run is its own object, so a loan can name the
  /// run it was made from.
  Object? _run;

  /// True while a checkout is running.
  bool get busy => _run != null;

  /// Runs [work], refusing to start while another run is in flight.
  ///
  /// Throws [GetPayInSessionBusyError] when a checkout is already running, unless this one
  /// was started inside [lend] by the holder of the guard.
  Future<T> run<T>(Future<T> Function() work) async {
    if (_run != null) {
      return _runLent(work);
    }

    final run = Object();

    _run = run;

    try {
      return await work();
    } finally {
      _run = null;
    }
  }

  /// Runs [work] with the place of the checkout holding this guard lent to one checkout
  /// that [work] opens.
  ///
  /// The payment sheet holds the guard while it is open, and a saved card's charge runs on
  /// the merchant's own server, which can answer with an issuer challenge the app has to
  /// open as a checkout of its own. Refusing that one would leave every saved card whose
  /// issuer asks for a challenge unpayable. The loan reaches only what [work] calls, through
  /// the zone it runs in, so a checkout opened from anywhere else is refused as before; it
  /// covers one checkout at a time, that checkout never frees the holder's place, and it
  /// ends with [work]: a timer or a listener [work] left behind cannot use it later.
  ///
  /// It also ends with the holder. A saved card's charge can outlast the sheet that started
  /// it, and by the time its challenge comes back another checkout may hold the place: the
  /// loan belongs to the run it was made from, and lends nothing once that run is over.
  Future<T> lend<T>(Future<T> Function() work) async {
    final loan = _Loan(this, _run);

    try {
      return await runZoned(work, zoneValues: <Object, Object>{_loanKey: loan});
    } finally {
      loan.ended = true;
    }
  }

  /// Runs a checkout started while this guard is held, if the holder lent it the place.
  Future<T> _runLent<T>(Future<T> Function() work) async {
    final loan = Zone.current[_loanKey];

    if (loan is! _Loan ||
        !identical(loan.guard, this) ||
        loan.run == null ||
        !identical(loan.run, _run) ||
        loan.taken ||
        loan.ended) {
      throw const GetPayInSessionBusyError();
    }

    loan.taken = true;

    try {
      return await work();
    } finally {
      loan.taken = false;
    }
  }
}

/// The zone value [SessionGuard.lend] marks its work with.
final Object _loanKey = Object();

/// One holder's place, lent to whatever its work opens.
class _Loan {
  /// Creates the loan of [guard]'s place, as [run] holds it.
  _Loan(this.guard, this.run);

  /// The guard whose place this is.
  final SessionGuard guard;

  /// The run that lent its place, or null when nothing held the guard.
  final Object? run;

  /// True while a checkout is running on the loan.
  bool taken = false;

  /// True once the work the place was lent to has finished.
  bool ended = false;
}
