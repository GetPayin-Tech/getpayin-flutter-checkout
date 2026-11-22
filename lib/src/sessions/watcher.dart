/// Something started for the length of one checkout and stopped when it ends.
///
/// The deep-link listener and the browser sheet's dismissal listener are both this, so the
/// browser session can stop them the same way in its `finally` without caring which is
/// which.
abstract interface class CheckoutWatcher {
  /// Stops watching. Called exactly once, when the checkout ends.
  void stop();
}

/// A watcher built from the cancel function its source handed back.
class CallbackWatcher implements CheckoutWatcher {
  /// Wraps [_stop] as a watcher.
  const CallbackWatcher(this._stop);

  final void Function() _stop;

  @override
  void stop() => _stop();
}
