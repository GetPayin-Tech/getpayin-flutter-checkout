import '../core/url.dart';

/// Whether a resource error the web view reported was the checkout page failing.
///
/// Android says which frame the error came from; iOS reports only navigation failures,
/// which are the page by definition and leave the field unset. An unset field therefore
/// means the page, and a sub-frame that fails — an analytics beacon on the issuer's
/// 3-D Secure page, say — does not take a working checkout down with it.
bool isMainFrameFailure(bool? isForMainFrame) => isForMainFrame ?? true;

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
