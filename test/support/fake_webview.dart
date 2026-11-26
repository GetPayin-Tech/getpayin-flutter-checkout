import 'dart:convert';

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

  /// Reports that the page itself could not be loaded, with the platform's [errorCode].
  void failLoading({int errorCode = -1}) => delegate?.onWebResourceError?.call(
        WebResourceError(errorCode: errorCode, description: 'no connection'),
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
  ///
  /// That page posts only once the host has started it, and puts on every message the key
  /// the host handed it then. A page the host has not started yet is started first, as a
  /// real web view would have when it finished loading.
  void post(String message) {
    if (_pageKey() == null && navigation?.onPageFinished != null) {
      finishLoading();
    }

    postAsFrame(_withPageKey(message));
  }

  /// Posts a message the way anything else on the page would: a frame inside it, or a page
  /// from before the key, neither of which has the key to put on it.
  void postAsFrame(String message) {
    final channel = channels.values.firstOrNull;

    if (channel == null) {
      throw StateError('The host registered no channel on this web view.');
    }

    channel.onMessageReceived(JavaScriptMessage(message: message));
  }

  /// The key the host handed this page when it last started it, if it has.
  String? _pageKey() {
    for (final script in scripts.reversed) {
      final key = RegExp(r'"pageKey":"([0-9a-f]+)"').firstMatch(script);

      if (key != null) {
        return key.group(1);
      }
    }

    return null;
  }

  /// [message] with this page's key on it, unless it carries one already.
  String _withPageKey(String message) {
    final key = _pageKey();
    final Object? decoded;

    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return message;
    }

    if (key == null ||
        decoded is! Map<String, Object?> ||
        decoded.containsKey('pageKey')) {
      return message;
    }

    return jsonEncode(<String, Object?>{...decoded, 'pageKey': key});
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

  /// Reports that this controller's page changed its own address without loading a page.
  ///
  /// What Android reports for a fragment the page sets on itself, which never reaches the
  /// navigation delegate there.
  void changeUrl(String url) {
    final onUrlChange = navigation?.onUrlChange;

    if (onUrlChange == null) {
      throw StateError('This web view does not watch its address.');
    }

    onUrlChange(UrlChange(url: url));
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

  /// Set to have every script the host runs fail, as it does on a web view that is gone.
  Object? scriptFailure;

  /// What a script run for its result answers, as the card page's start does: true when the
  /// page has its script. Set to false for an address that served some other page.
  Object startAnswer = true;

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final failure = scriptFailure;

    if (failure != null) {
      throw failure;
    }

    scripts.add(javaScript);

    return startAnswer;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    final failure = scriptFailure;

    if (failure != null) {
      throw failure;
    }

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

  /// What the page's host does when the page changes its own address.
  UrlChangeCallback? onUrlChange;

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    this.onUrlChange = onUrlChange;
  }

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
