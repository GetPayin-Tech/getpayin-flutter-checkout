import 'dart:async';

import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// A launcher that records what it was asked to open instead of opening it.
///
/// It also records whether anything asked it *whether* a link can be opened: that question
/// answers no for every scheme the host app has not declared, so a 3-D Secure bank step
/// would silently do nothing if the package ever started asking it.
class FakeUrlLauncher extends UrlLauncherPlatform {
  /// Installs a fresh fake as the platform and hands it back.
  static FakeUrlLauncher install() {
    final launcher = FakeUrlLauncher();

    UrlLauncherPlatform.instance = launcher;

    return launcher;
  }

  /// Every link it was asked to launch, with the mode it was asked for.
  final List<(String url, PreferredLaunchMode mode)> launches =
      <(String, PreferredLaunchMode)>[];

  /// The links something asked it about rather than launching. Must stay empty.
  final List<String> asked = <String>[];

  /// How many times an in-app browser view was closed.
  int closes = 0;

  /// What a launch answers. False is "nothing on this phone can open it".
  bool opens = true;

  /// Set to have a launch answer only when the test completes it, as a slow phone does.
  Completer<bool>? answer;

  /// Unused: the package launches links itself rather than through a Link widget.
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async {
    asked.add(url);

    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));

    return answer?.future ?? opens;
  }

  @override
  Future<void> closeWebView() async {
    closes += 1;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => true;
}
