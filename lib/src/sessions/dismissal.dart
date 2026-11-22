import 'package:flutter/widgets.dart';

import 'watcher.dart';

/// Decides when the browser sheet has been dismissed, from the app's own lifecycle.
///
/// There is no callback for a dismissed Custom Tab or Safari sheet: the app is simply in
/// front again. Opening one puts the app behind it, so the first return to the foreground
/// afterwards is the sheet going away — whether the payer closed it or the return link
/// brought the app forward. Which of the two it was is settled by the grace period in
/// `runBrowserCheckout`, not here.
///
/// Arming on *any* state other than resumed is deliberate. Android reports the app paused
/// behind a Custom Tab; iOS reports it inactive or hidden behind a Safari sheet. A state
/// change the sheet did not cause cannot produce a false dismissal, because while the sheet
/// is in front the app cannot reach resumed again without it going away.
class SheetDismissalDetector {
  bool _away = false;

  /// True the first time the app comes back to the foreground after leaving it.
  bool observe(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _away = true;

      return false;
    }

    if (!_away) {
      return false;
    }

    _away = false;

    return true;
  }
}

/// Watches the app's lifecycle for the browser sheet being dismissed.
CheckoutWatcher watchSheetDismissal(void Function() onDismissed) {
  final detector = SheetDismissalDetector();
  final listener = AppLifecycleListener(
    onStateChange: (state) {
      if (detector.observe(state)) {
        onDismissed();
      }
    },
  );

  return CallbackWatcher(listener.dispose);
}
