# Setup

Everything you need in place before a payment can work, and the configuration the wallets
depend on.

## Prerequisites

1. **A real build on a real device.** A simulator has no wallet, and the return link needs
   your app's own scheme, which is native configuration.
2. **A GetPayIn integration of type "Mobile App"**, with **Mobile App Return Scheme** set
   to your app's scheme. Set it in the GetPayIn dashboard under
   **Settings → Payment Integrations**.
3. **Your own server.** It calls `POST /api/integration/init` to create the payment and
   confirms the result afterwards. Your hash token stays there and never goes into the app.

## Install

```bash
flutter pub add getpayin_flutter_checkout
```

That brings in `webview_flutter` for the in-app screen, `url_launcher` for the browser
sheet and the 3-D Secure bank links, and `app_links` for the return link. Then rebuild: the
web view is native code.

## Your app's scheme

The return link is built from your app's scheme, and it has to match the integration's
**Mobile App Return Scheme** exactly. Flutter has no `app.json`, so declare it in both
native projects.

**`android/app/src/main/AndroidManifest.xml`**, inside the `<activity>` that is already
there:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="myapp" />
</intent-filter>
```

**`ios/Runner/Info.plist`**:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myapp</string>
    </array>
  </dict>
</array>
```

With that, `myapp://payment-return` is your return link. The path can be anything you like,
as long as the dashboard and your `open()` call agree on it.

## Declaring every scheme your app answers to

```dart
void main() {
  declareHostAppSchemes(const ['myapp', 'com.shop.app', 'shopdeep']);
  runApp(const MyApp());
}
```

The checkout refuses these whenever a link is not the return link, so a page inside the
checkout cannot drive your app's deep-link routes. List everything: every
`android:scheme` in your manifest, every `CFBundleURLSchemes` entry in your `Info.plist`,
and your application id if you registered it as a scheme.

The Expo package reads these out of `app.json`. Flutter has no app config to read at
runtime, so this one call is the whole of it. Declaring nothing leaves the return link's own
scheme as the only one refused, which is the floor rather than the whole rule.

## The provider

Mount it once, under your app and above the screens that take payments:

```dart
MaterialApp(
  home: GetPayInProvider(child: const ShopPage()),
)
```

It presents the checkout as a full-screen route on your app's own `Navigator`, which keeps
the browser's bar off the payer's screen and makes the system back button close the
checkout. `GetPayInCheckout.open()` needs it on iOS, and on Android once `googlePayInApp`
is on. Without it, an in-app checkout fails with `GetPayInProviderMissingError`.

It needs a `Navigator` to present on. Mounted as above it finds your app's. Mounted above
one — in `MaterialApp.builder`, or in a `go_router` shell — hand it the same key:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => GetPayInProvider(
    navigatorKey: navigatorKey,
    child: child,
  ),
  home: const ShopPage(),
)
```

## go_router

A router treats the returning deep link as a route, so an app that has no
`/payment-return` route shows an error page on top of a checkout that has already been
paid. One redirect fixes it:

```dart
final paymentReturn = PaymentReturnRedirect('myapp://payment-return');

final router = GoRouter(
  redirect: (context, state) => paymentReturn.redirectFor(state.uri.toString()),
  routes: [...],
);
```

By the time that link arrives the package already has the result: the in-app web view read
it off the navigation, and the browser sheet read it off the deep link. The redirect only
keeps the router out of the way, sending the payer to `/` — pass `initialPath` for
somewhere else. Matching is on whole path segments, so your own
`/help/payment-returns-policy` route still opens normally.

With Navigator 1.0 and `MaterialApp.home` there is nothing to do: an unmatched deep link
lands on your first screen anyway.

## iOS

Apple Pay needs no configuration in your app. It works in the checkout screen as long as
you use the package's view as it is, because WebKit turns Apple Pay off on any page the
host app has added scripts to. This package registers no JavaScript channel on the checkout
web view and never calls `runJavaScript` on it; if you wrap a web view of your own around
the checkout, do the same.

A 3-D Secure step that hands the payer to their **bank's app** needs nothing either. The
package opens the link directly rather than asking whether it can, so there are no bank
schemes to declare in `LSApplicationQueriesSchemes`.

## Android

Nothing to configure for Google Pay in the browser sheet, which is the default.

For Google Pay **inside your app's own screen** (`googlePayInApp: true`), Android's WebView
has to be allowed to find the payment apps on the phone. Add this to
`android/app/src/main/AndroidManifest.xml`, as a direct child of `<manifest>`:

```xml
<queries>
  <intent>
    <action android:name="org.chromium.intent.action.PAY" />
  </intent>
  <intent>
    <action android:name="org.chromium.intent.action.IS_READY_TO_PAY" />
  </intent>
  <intent>
    <action android:name="org.chromium.intent.action.UPDATE_PAYMENT_DETAILS" />
  </intent>
</queries>
```

Without those three, the Payment Request API cannot see Google Pay and the button simply
does not appear — no error, no log line. The package turns the API itself on for you
(`AndroidWebViewController.setPaymentRequestEnabled`), before the page loads, where it has
to be set.

Then see [Google Pay on Android](google-pay.md) for Google's approval, which is what
`googlePayInApp` waits for.

## What not to do

1. **Do not pass `checkoutUrl` through a route parameter.** A router decodes it a second
   time, which breaks the link's signature and the checkout answers HTTP 403. Keep it in
   memory and hand it straight to `open()`.
2. **Do not add scripts to the checkout view.** No JavaScript channel, no `runJavaScript`,
   nothing. WebKit turns Apple Pay off on any page the host app has added scripts to, with
   no error to say so.
3. **Do not change the web view's user agent.** Google checks it, and it has to end with
   `GOOGLE_PAY_SUPPORTED`.
4. **Do not use the checkout's `iframe` mode.** It only allows the integration's registered
   website as the page around it, and an app screen has none.

## Next

[Taking payments](taking-payments.md).
