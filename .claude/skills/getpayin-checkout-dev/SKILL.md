---
name: getpayin-checkout-dev
description: Work on the getpayin_checkout package itself: its layering rules, the settings that fail silently on a phone, the invariants only review catches, and the verify loop. Use when editing, reviewing or testing files under lib/src/core, lib/src/webview, lib/src/sessions, lib/src/sheet or lib/src/widgets in the getpayin-flutter-checkout repository, when adding an export or option to it, or when a change touches the return-link reader, the presentation rule, the navigation classifier, the deep-link watcher, the payment sheet or the hosted-fields bridge.
---

# Working on getpayin_checkout

The maintainer's skill for the package itself. For integrating it into an app, use
`getpayin-checkout` instead.

## Before changing anything

Read [`doc/architecture.md`](../../../doc/architecture.md) and
[`doc/security.md`](../../../doc/security.md). Everything below summarises those two; they
carry the reasoning.

## Layering

| Layer      | Directory               | May import                                                    |
| ---------- | ----------------------- | ------------------------------------------------------------- |
| Pure logic | `lib/src/core`          | nothing outside itself                                        |
| Web view   | `lib/src/webview`       | `lib/src/core`, plus the one exception below                  |
| Sessions   | `lib/src/sessions`      | `lib/src/core`, `url_launcher`, `app_links`, Flutter          |
| Sheet      | `lib/src/sheet`         | `lib/src/core`, `lib/src/webview`, Flutter, `webview_flutter` |
| Widgets    | `lib/src/widgets`       | Flutter, `webview_flutter`, the layers above                  |
| Facade     | `lib/src/checkout.dart` | `lib/src/platform.dart` only                                  |

The one exception in `lib/src/webview` is `external_link.dart`, which imports
`url_launcher`. Its launcher is injectable so the rule around it keeps its tests. Do not
add a second without a reason that good. `lib/src/platform.dart` is the only place that
asks Flutter which platform this is.

Moving a rule out of `core` or `webview` into a widget makes it untestable, and these are
rules that fail silently on a phone rather than throwing.

## One source of truth per rule

| Rule                           | Where                                         |
| ------------------------------ | --------------------------------------------- |
| What a claim of payment means  | `core/return_url.dart` → `settlePaidClaim`    |
| What a return link says        | `core/return_url.dart` → `readCheckoutResult` |
| Where the checkout is drawn    | `core/presentation.dart`                      |
| What to do with a navigation   | `core/navigation.dart`                        |
| What counts as the same scheme | `core/url.dart` → `normalizeScheme`           |
| The web view wallet settings   | `webview/platform_settings.dart`              |
| One checkout at a time         | `core/session_guard.dart`                     |
| Every text a payer can see     | `core/messages.dart`                          |
| Settle-once                    | `core/deferred.dart`                          |

Writing a second copy of one of these is the bug.

## Invariants only review catches

1. **A claim of payment is never upgraded.** An unknown or absent status becomes `notPaid`.
   Both the return link and a hosted-fields charge end at `settlePaidClaim`: only `PAID` is
   paid, and a paid claim for another invoice is refused. A third source must go through it
   too.
2. **One parser, two readings.** `readReturnClaim` reports what a link says;
   `readCheckoutResult` adds the rule that an unpaid invoice is not a payment, and
   `readCardSave` deliberately does not — a verification run is _meant_ to end unpaid, so
   reading a save with the payment rule would call every success a failure. Never add a
   second parser: the strictness that refuses a repeated or ambiguous field has to be the
   same for both, because it is the same signed link.
3. **A checkout only hears links that arrive while it is watching.** Neither source is tied
   to a live checkout: the initial link answers with the first link the process ever saw,
   whenever that arrived, and links that arrive before Dart listens are replayed to the
   first listener. So `ReturnLinkWatcher` holds one subscription for the process, opened by
   `prime()` as the provider mounts, reads the initial link once there, and drops anything
   that arrives with nothing waiting for it. Do not move the subscription into `watch()`,
   and do not read the initial link there: both are how a link that belongs to nothing ends
   up settling the next payment.
4. **`expectedInvoiceId` downgrades only a paid result.** Rewriting a `notPaid` or
   `cancelled` would lose the reason the payer was given.
5. **A script scheme, any scheme the app answers to, and anything with no part in paying
   never reach the launcher.** `classifyNavigation` returns `block` for all three. The app's
   schemes come from `declareHostAppSchemes`, because Flutter has no app config to read.
6. **A frame navigating itself can only ever load.** `isTopFrame` is required, never
   defaulted: a 3-D Secure page knows the real invoice id, so a frame aimed at the return
   link would report a payment nobody made, and `expectedInvoiceId` is no defence.
   `webview_flutter` reports `isMainFrame` on both platforms, so unlike the Expo package the
   rule holds on Android too. Keep it that way — and keep what is written about it exact: it
   names the frame being navigated, not the frame that asked, which no web view reports.
7. **No script on a surface that can show a wallet.** WebKit turns Apple Pay off on any page
   the host app has scripted. The hosted checkout view and `WalletSurface` register no
   channel and never run JavaScript; `WalletSurface` answers by navigating to the return
   link. A test asserts it. The sheet's card box _is_ scripted, deliberately: it shows no
   wallet, and the alternative would put the client token in the page's URL.
8. **Both sides of an invoice comparison go through `core/invoice_id.dart`.** The server
   sends a number and the link carries text.
9. **A payer never sees developer text.** `buildCheckoutSource`'s `error` names an option
   and its value, so it goes to `onLoadError`'s second argument and the payer gets
   `loadErrorMessage`. Blank option text falls back through `core/text.dart`.
10. **The navigation handler is keyed to the checkout, not the callbacks.** It completes at
   most once; rebuilding it on an ordinary rebuild resets that latch and reports one payment
   twice.
11. **A failed load always shows a way out.** Otherwise the `open()` future never settles and
    `SessionGuard` reports busy for the rest of the process.
12. **Android's Payment Request switch is set before the page loads.** Set after, the payer
    gets a checkout with no Google Pay button and nothing in the log.
13. **The card box is built when the sheet opens, not when the payer asks for it.** It has a
    page to load and fields to mount; lazily built, none of that starts until it is too late.
14. **A fatal fields failure closes the sheet after the frame, never during it.** A route
    cannot be popped while it is being built.
15. **The card box answers one charge: its own.** Its channel is shared with everything the
    page frames and neither platform names the sender, so a `payment` arriving while no
    charge of the box's is running is ignored, and only a page from the registered origin
    may hold its top frame. A frame may still load: the gateway's fields and the issuer's
    step are rendered that way.

## House style

1. **A doc comment on every declaration**, saying why when the reason is not obvious from the
   name. `webview/platform_settings.dart` is the model: each setting says what breaks.
2. **No comments inside function bodies.** Extract a named helper instead. A block comment
   above a declaration, or a file header, is fine.
3. `dart format` is the authority on layout, which is why `require_trailing_commas` is not
   enabled: a lint that fights the formatter is a lint that loses.

## The loop

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
npx markdownlint-cli@0.50.0 '**/*.md'
```

CI runs the same five, plus the coverage gate and `flutter pub publish --dry-run`, so a
green run of them is a green pipeline.

Narrow while iterating:

```bash
flutter test test/return_url_test.dart
flutter test --plain-name 'takes a new card'
```

Every file carrying a rule is covered line for line and CI enforces it. Two lines are
exempt, both a plugin's own constructor: `DeepLinkSource.platform` and the pair of
`AndroidWebViewController` calls that turn Google Pay on.

## Adding to the public surface

1. Add the type with a doc comment.
2. Thread it through `core/return_url.dart` if it affects what a payment claim means, so
   every presentation gets it.
3. Export it from `lib/getpayin_checkout.dart`.
4. Add it to `doc/api.md`. The reference is expected to be complete.
5. Note it in `CHANGELOG.md`.

## Testing notes

- The suite runs in the Dart VM with every plugin replaced by something a test drives:
  `test/support/fake_webview.dart` (navigations, page events, JS channels and scripts),
  `test/support/fake_launcher.dart` (which mode each link was launched with),
  `DeepLinkSource` (its two sources as functions) and `BrowserCheckoutPorts` (the whole
  browser flow as a value).
- Widget tests pump fixed frames rather than `pumpAndSettle`: the checkout draws an
  indeterminate progress indicator, which never settles.
- Choose the presentation per checkout in a widget test rather than overriding
  `debugDefaultTargetPlatformOverride`: a widget test checks its invariants before its own
  `tearDown` runs.
- `test/launch_url_test.dart` builds a fresh `ReturnLinkWatcher` per test, because the launch
  link is consumed once per watcher.
- When fixing a bug, write the failing test first. `test/launch_url_test.dart` and
  `test/return_url_spoofing_test.dart` exist because they caught real ones.

## Before a release

The suite cannot test a phone. Run the by-hand checks in
[`CONTRIBUTING.md`](../../../CONTRIBUTING.md): Apple Pay in the app's own screen on iOS, a
3-D Secure card step, closing giving `cancelled`, Google Pay in the app's own screen on an
approved Android build, Google Pay in the browser sheet on an unapproved one, and the system
back button closing the in-app checkout.
