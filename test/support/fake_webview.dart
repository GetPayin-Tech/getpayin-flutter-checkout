import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A web view platform that draws nothing and lets a test drive the navigation delegate.
///
/// The checkout screen's behaviour — presenting, completing, failing closed with a way out
/// — is the part no pure test can reach, because it only happens once a real web view
/// reports a navigation. This stands in for that web view.
class FakeWebViewPlatform extends WebViewPlatform {
  /// Installs a fresh fake as the platform and hands it back.
  static FakeWebViewPlatform install() {
    final platform = FakeWebViewPlatform();

    WebViewPlatform.instance = platform;

    return platform;
  }

  /// Every controller the widgets created, newest last.
  final List<FakeWebViewController> controllers = <FakeWebViewController>[];

  /// The delegate of the checkout being shown.
  FakeNavigationDelegate? delegate;

  /// Set before a web view is created to have loading fail as a broken one does.
  Object? loadFailure;

  /// The page the newest web view was asked to load.
  Uri? get loadedUri =>
      controllers.isEmpty ? null : controllers.last.loaded.lastOrNull;

  /// Reports a navigation the way a real web view does, and answers what it was told.
  Future<NavigationDecision> navigate(String url,
      {bool isMainFrame = true}) async {
    final onNavigationRequest = delegate?.onNavigationRequest;

    if (onNavigationRequest == null) {
      throw StateError('No checkout web view is listening for navigations.');
    }

    return onNavigationRequest(
      NavigationRequest(url: url, isMainFrame: isMainFrame),
    );
  }

  /// Reports that a page started loading, which is what an HTTP error is judged against.
  void startLoading(String url) => delegate?.onPageStarted?.call(url);

  /// Reports that a request answered an HTTP error.
  void httpError({required String uri, int status = 403}) {
    delegate?.onHttpError?.call(
      HttpResponseError(
        request: WebResourceRequest(uri: Uri.parse(uri)),
        response: WebResourceResponse(uri: Uri.parse(uri), statusCode: status),
      ),
    );
  }

  /// Reports that the page finished loading.
  void finishLoading() => delegate?.onPageFinished?.call('');

  /// Reports that the page itself could not be loaded.
  void failLoading() => delegate?.onWebResourceError?.call(
        WebResourceError(errorCode: -1, description: 'no connection'),
      );

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params)..loadFailure = loadFailure;

    controllers.add(controller);

    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return delegate = FakeNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }
}

/// A controller that records what it was told instead of touching a web view.
class FakeWebViewController extends PlatformWebViewController {
  /// Creates the fake controller.
  FakeWebViewController(super.params) : super.implementation();

  /// The pages this controller was asked to load, in order.
  final List<Uri> loaded = <Uri>[];

  /// Set to have loading fail the way a web view with no page can.
  Object? loadFailure;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded.add(params.uri);

    final failure = loadFailure;

    if (failure != null) {
      throw failure;
    }
  }
}

/// A delegate that keeps the callbacks so a test can fire them.
class FakeNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates the fake delegate.
  FakeNavigationDelegate(super.params) : super.implementation();

  /// What the checkout does with a navigation.
  NavigationRequestCallback? onNavigationRequest;

  /// What the checkout does when a page starts loading.
  PageEventCallback? onPageStarted;

  /// What the checkout does when a page finishes loading.
  PageEventCallback? onPageFinished;

  /// What the checkout does when a page fails to load.
  WebResourceErrorCallback? onWebResourceError;

  /// What the checkout does when a request answers an HTTP error.
  HttpResponseErrorCallback? onHttpError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    this.onHttpError = onHttpError;
  }
}

/// A web view widget that occupies its space and draws nothing.
class FakeWebViewWidget extends PlatformWebViewWidget {
  /// Creates the fake widget.
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
