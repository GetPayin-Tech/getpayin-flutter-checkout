import '../errors.dart';

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
