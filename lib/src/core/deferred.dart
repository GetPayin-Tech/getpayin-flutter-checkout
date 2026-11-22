import 'dart:async';

/// A future with its settle functions exposed, which only settles once.
///
/// The return link can reach the app from more than one source at the same time — a web
/// view navigation, a deep-link event and the link the app was cold-started with — and the
/// payer can close the screen while one is in flight. Dropping every settle after the first
/// is what keeps those races from producing two results for one checkout, where a bare
/// [Completer] would throw on the second.
class Deferred<T> {
  final Completer<T> _completer = Completer<T>();

  /// The future that settles once.
  Future<T> get future => _completer.future;

  /// True once this has settled, either way.
  bool get settled => _completer.isCompleted;

  /// Settles with [value], or does nothing if something already settled this.
  void resolve(T value) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.complete(value);
  }

  /// Settles with [error], or does nothing if something already settled this.
  void reject(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }

    _completer.completeError(error, stackTrace);
  }
}
