import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A web view platform that draws nothing and lets a test drive the pages it creates.
///
/// What happens on a checkout screen — presenting, completing once, failing closed with a
/// way out — only happens when a real web view reports a navigation or a page event. This
/// stands in for that web view, one instance per page the app opens.
class FakeWebViewPlatform extends WebViewPlatform {
  /// Installs a fresh fake as the platform and hands it back.
  static FakeWebViewPlatform install() {
    final platform = FakeWebViewPlatform();

    WebViewPlatform.instance = platform;

    return platform;
  }

  /// Every controller the widgets created, newest last.
  final List<FakeWebViewController> controllers = <FakeWebViewController>[];

  /// The delegate of the page created most recently.
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
      throw StateError('No web view is listening for navigations.');
    }

    return onNavigationRequest(
        NavigationRequest(url: url, isMainFrame: isMainFrame));
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

  /// The headers it was asked to send with the most recent load.
  Map<String, String> headers = const <String, String>{};

  /// The channels the host registered on this page, by name.
  final Map<String, JavaScriptChannelParams> channels =
      <String, JavaScriptChannelParams>{};

  /// Every script the host asked this page to run, in order.
  final List<String> scripts = <String>[];

  /// The delegate this controller reports its page events to.
  FakeNavigationDelegate? navigation;

  /// Set to have loading fail the way a web view with no page can.
  Object? loadFailure;

  /// Posts a message to the host the way this page's own script does.
  void post(String message) {
    final channel = channels.values.firstOrNull;

    if (channel == null) {
      throw StateError('The host registered no channel on this web view.');
    }

    channel.onMessageReceived(JavaScriptMessage(message: message));
  }

  /// Reports a navigation on this controller's own page, and answers what it was told.
  ///
  /// Per controller rather than per platform: a sheet has a card box and a wallet surface
  /// open at once, and each judges its own navigations.
  Future<NavigationDecision> navigate(String url,
      {bool isMainFrame = true}) async {
    final onNavigationRequest = navigation?.onNavigationRequest;

    if (onNavigationRequest == null) {
      throw StateError('This web view judges no navigations.');
    }

    return onNavigationRequest(
        NavigationRequest(url: url, isMainFrame: isMainFrame));
  }

  /// Reports that this controller's own page finished loading.
  void finishLoading() {
    final onPageFinished = navigation?.onPageFinished;

    if (onPageFinished == null) {
      throw StateError(
          'This web view has no delegate listening for page events.');
    }

    onPageFinished(loaded.lastOrNull.toString());
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {
    navigation = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded.add(params.uri);
    headers = params.headers;

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
