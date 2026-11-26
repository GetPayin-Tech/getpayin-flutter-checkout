import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
// Material moved to package:material_ui after Flutter 3.47, which does not exist in the
// older versions this package still supports. The import stays until the floor moves.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../core/messages.dart';
import '../core/text.dart';
import '../errors.dart';
import '../sessions/deep_link.dart';
import '../sessions/registry.dart';
import '../sessions/session_host.dart';
import '../types.dart';
import 'checkout_style.dart';
import 'getpayin_checkout_view.dart';

/// Hosts the in-app checkout screen.
///
/// Mount it once, under your app and above the screens that take payments, and
/// `GetPayInCheckout.open` can present a checkout from anywhere:
///
/// ```dart
/// MaterialApp(
///   home: GetPayInProvider(child: const ShopPage()),
/// )
/// ```
///
/// It presents the checkout as a full-screen route on your app's own `Navigator`, which is
/// what keeps the browser's own bar off the payer's screen and makes the system back button
/// close the checkout the way a payer expects.
///
/// It therefore needs a `Navigator` to present on. Mounted below one, as above, it finds the
/// app's. Mounted above one — in `MaterialApp.builder`, say — give it the same
/// [navigatorKey] you give `MaterialApp`.
class GetPayInProvider extends StatefulWidget {
  /// Creates a provider around [child].
  const GetPayInProvider({this.child, this.navigatorKey, super.key});

  /// The app below this provider.
  final Widget? child;

  /// The navigator to present the checkout on, for a provider mounted above it.
  ///
  /// Pass the same key you pass to `MaterialApp.navigatorKey`. Without it the provider uses
  /// the root navigator it can see from its own position in the tree.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<GetPayInProvider> createState() => _GetPayInProviderState();
}

class _GetPayInProviderState extends State<GetPayInProvider> {
  late final CheckoutSessionHost _host = CheckoutSessionHost(_onSessionChanged);

  NavigatorState? _navigator;
  Route<void>? _route;

  @override
  void initState() {
    super.initState();
    registerPresenter(_present);
    unawaited(returnLinkWatcher.prime());
  }

  @override
  void dispose() {
    unregisterPresenter(_present);
    _navigator = null;
    _route = null;
    _host.dispose();
    super.dispose();
  }

  /// Presents [request] and completes once the checkout ends.
  ///
  /// The navigator is resolved before the host is told to present anything, so an app that
  /// mounted the provider where no navigator can be reached is told so instead of being
  /// left with a session that can never be shown or settled.
  Future<CheckoutResult> _present(CheckoutRequest request) {
    _navigator = _resolveNavigator();

    return _host.present(request);
  }

  NavigatorState _resolveNavigator() {
    final navigator = widget.navigatorKey?.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);

    if (navigator == null) {
      throw const GetPayInProviderMissingError.withoutNavigator();
    }

    return navigator;
  }

  void _onSessionChanged(CheckoutRequest? request) {
    if (request == null) {
      _dismissScreen();

      return;
    }

    _showScreen(request);
  }

  void _showScreen(CheckoutRequest request) {
    final navigator = _navigator;

    if (navigator == null) {
      return;
    }

    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _CheckoutScreen(
        request: request,
        onFinish: (result) => _whileOpen(request, () => _host.finish(result)),
        onCancel: ([message]) =>
            _whileOpen(request, () => _host.cancel(message)),
        onUnconfirmed: (result) =>
            _whileOpen(request, () => _host.holdUnconfirmed(result)),
        onGone: () => _whileOpen(request, () {
          _route = null;
          _host.cancel(closedByAppMessage);
        }),
      ),
    );

    _route = route;
    navigator.push(route);
  }

  /// Runs [settle] only while [request] is still the checkout the host has open.
  ///
  /// The guard is free the moment a checkout settles, so the next one can open while the
  /// old screen is still on its way out, and that screen goes on reporting until it has
  /// gone. Through the host, its answer or its leaving would end the new checkout instead.
  void _whileOpen(CheckoutRequest request, void Function() settle) {
    if (identical(_host.current, request)) {
      settle();
    }
  }

  /// Takes the checkout screen away once the session has settled.
  ///
  /// The references are cleared first: this also runs while the provider is being disposed,
  /// where touching the navigator is both pointless and unsafe.
  void _dismissScreen() {
    final navigator = _navigator;
    final route = _route;

    _route = null;

    if (navigator == null || route == null || !route.isActive) {
      return;
    }

    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}

/// The screen one in-app checkout is drawn on.
class _CheckoutScreen extends StatefulWidget {
  const _CheckoutScreen({
    required this.request,
    required this.onFinish,
    required this.onCancel,
    required this.onUnconfirmed,
    required this.onGone,
  });

  final CheckoutRequest request;
  final void Function(CheckoutResult result) onFinish;
  final void Function([String? message]) onCancel;

  /// Called with what the checkout settles as from now on if it goes without an answer.
  final void Function(CheckoutResult result) onUnconfirmed;

  /// Called as the screen goes, answered or not.
  ///
  /// The provider settles the checkout then if nothing else has, without touching the
  /// navigator: the screen is already off it, and the navigator may be going too.
  final VoidCallback onGone;

  @override
  State<_CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<_CheckoutScreen> {
  String? _loadError;

  /// True once a page of the checkout has finished loading.
  bool _pageLoaded = false;

  /// Settles the checkout if its screen goes without an answer.
  ///
  /// The app can take the screen away in its own code, with a pop or a reset of its screens
  /// on sign-out, and neither asks the screen first. Unsettled, the `open()` future would
  /// stay pending and the guard would report busy for the rest of the process. After an
  /// answer this does nothing: a checkout settles once.
  @override
  void dispose() {
    widget.onGone();
    super.dispose();
  }

  /// Reports a failure to the payer, and in a debug build the cause to the log.
  ///
  /// The detail names the option and the value it got, so it never reaches the screen. A
  /// release build's log is read by whoever can read the phone's, and a cause from the web
  /// view can carry the checkout's signed link, so it is printed only while developing.
  ///
  /// A failure after the checkout page had loaded may come after the charge, and the page
  /// that would have said so may be the one that failed. From then on, however the
  /// checkout goes without an answer, the app is told that nobody can confirm it, never
  /// that nothing happened. Taken as the failure arrives: a failed page finishes loading
  /// too.
  void _onLoadError(String message, String? detail) {
    if (detail != null && kDebugMode) {
      debugPrint('GetPayIn checkout: $detail');
    }

    if (!mounted) {
      return;
    }

    if (_pageLoaded) {
      widget.onUnconfirmed(
        CheckoutResult(
          status: CheckoutStatus.notPaid,
          code: CheckoutResultCode.outcomeUnknown,
          message: message,
        ),
      );
    }

    setState(() => _loadError = message);
  }

  void _onPageLoaded() => _pageLoaded = true;

  /// Closes the checkout at the payer's request, with the close button or Back.
  void _close() => widget.onCancel(_loadError);

  /// Whether the top bar is drawn, which is the payer's only way to close the checkout.
  ///
  /// A checkout that cannot load would otherwise be a blank screen, and with the bar hidden
  /// there would be nothing to close it with. The session would never settle: the `open()`
  /// future would stay pending and the guard would report busy for the rest of the process,
  /// so every later checkout would be refused. A failure therefore always carries its own
  /// way out, whatever the caller asked for.
  bool get _headerShown =>
      widget.request.options.headerShown || _loadError != null;

  @override
  Widget build(BuildContext context) {
    final options = widget.request.options;
    final loadError = _loadError;
    final headerShown = _headerShown;

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: CheckoutStyle.background,
        body: SafeArea(
          left: false,
          right: false,
          child: Column(
            children: <Widget>[
              if (headerShown) _header(options),
              Expanded(
                key: const ValueKey<String>('checkout'),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _checkout(options)),
                    if (loadError != null)
                      Positioned.fill(child: _failure(loadError)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(OpenCheckoutOptions options) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: CheckoutStyle.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: CheckoutStyle.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  fallbackText(options.title, defaultCheckoutTitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CheckoutStyle.title,
                ),
              ),
              Semantics(
                button: true,
                label: fallbackText(
                    options.closeLabel, defaultCloseAccessibilityLabel),
                excludeSemantics: true,
                child: TextButton(
                  onPressed: _close,
                  child: Text(
                    fallbackText(options.closeLabel, defaultCloseLabel),
                    style: CheckoutStyle.action,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkout(OpenCheckoutOptions options) {
    return GetPayInCheckoutView(
      checkoutUrl: widget.request.checkoutUrl,
      returnUrl: options.returnUrl,
      expectedInvoiceId: options.expectedInvoiceId,
      ownSchemes: options.ownSchemes,
      loadErrorMessage: options.loadErrorMessage,
      linkErrorMessage: options.linkErrorMessage,
      onComplete: widget.onFinish,
      onLoadError: _onLoadError,
      onPageLoaded: _onPageLoaded,
    );
  }

  /// The failure, drawn over the checkout rather than in its place.
  ///
  /// The checkout stays loaded underneath: a page can fail after the charge, and an answer
  /// that still comes from it settles the checkout as it would have.
  Widget _failure(String message) {
    return ColoredBox(
      color: CheckoutStyle.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message,
              textAlign: TextAlign.center, style: CheckoutStyle.body),
        ),
      ),
    );
  }
}
