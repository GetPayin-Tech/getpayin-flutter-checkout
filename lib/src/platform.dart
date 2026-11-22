import 'package:flutter/foundation.dart';

/// The plain name of the platform the app is running on: `ios`, `android`, `macos`.
///
/// The rules that depend on the platform — where the checkout is drawn, which wallet
/// setting the web view needs — take this name as a value so they can be tested without a
/// phone. This is the one place that asks Flutter which platform it is, so a test that
/// overrides [debugDefaultTargetPlatformOverride] moves every rule at once.
String currentPlatformName() => defaultTargetPlatform.name.toLowerCase();
