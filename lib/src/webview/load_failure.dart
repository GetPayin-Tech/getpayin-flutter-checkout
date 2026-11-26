import '../core/url.dart';

/// Whether a resource error the web view reported was the checkout page failing.
///
/// Android says which frame the error came from; iOS reports only navigation failures,
/// which are the page by definition and leave the field unset. An unset field therefore
/// means the page, and a sub-frame that fails — an analytics beacon on the issuer's
/// 3-D Secure page, say — does not take a working checkout down with it.
bool isMainFrameFailure(bool? isForMainFrame) => isForMainFrame ?? true;

/// Whether an error the web view reported is a load it stopped rather than one that failed.
///
/// iOS reports both as navigation failures: `-999` is a load cancelled because another
/// took its place, as one bank redirect does another during 3-D Secure, and `102` is WebKit
/// stopping a load the checkout refused to let through. Neither is the page failing, and
/// read as one it would put an error over a payment that is still going. Android's codes
/// run from `-1` to `-16`, so these two never name one of its failures.
bool isInterruptedLoad(int errorCode) =>
    errorCode == _cancelled || errorCode == _interruptedByPolicy;

/// `NSURLErrorCancelled`.
const int _cancelled = -999;

/// `WebKitErrorFrameLoadInterruptedByPolicyChange`.
const int _interruptedByPolicy = 102;

/// Whether an HTTP error the web view reported was the checkout page itself answering.
///
/// An HTTP error is reported for every request the page makes, not only for the document,
/// so the status of some third-party script must not blank out a checkout that loaded. The
/// page the payer is on is what counts, and only an error carrying that same URL is the
/// page refusing to load — which is what a double-decoded `checkout_url` looks like: HTTP
/// 403 on the document itself.
bool isPageHttpFailure({String? failedUri, String? pageUri}) {
  if (failedUri == null || pageUri == null) {
    return false;
  }

  return isSameTarget(failedUri, pageUri);
}
