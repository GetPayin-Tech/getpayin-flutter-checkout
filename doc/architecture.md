# Architecture

For anyone changing the package. If you only want to use it, you do not need this page.

## The shape of it

The decision-making is pure Dart with no widgets and no plugins behind it. That is
deliberate: it is the part that decides whether a payment is reported correctly, and it has
to be testable without a phone.

```text
GetPayInCheckout.open()            lib/src/checkout.dart   imports the platform name only
  │
  ├─ resolvePresentation()         lib/src/core/           pure: which presentation
  ├─ assertCheckoutUrl()           lib/src/core/           pure: validation
  └─ SessionGuard                  lib/src/core/           pure: one checkout at a time
        │
        ├── in-app ──▶ registry ──▶ GetPayInProvider       widgets
        │                             └─ GetPayInCheckoutView
        │                                  └─ CheckoutNavigationHandler   pure
        │                                       ├─ classifyNavigation()   pure
        │                                       └─ resolveReturn()        pure
        │
        └── browser ─▶ runBrowserCheckout        url_launcher
                          ├─ ReturnLinkWatcher   app_links
                          ├─ SheetDismissalDetector  pure, over the app lifecycle
                          └─ resolveReturn()     pure
```

| Layer      | Directory                     | May import                                             |
| ---------- | ----------------------------- | ------------------------------------------------------ |
| Pure logic | `lib/src/core`                | nothing outside itself                                 |
| Web view   | `lib/src/webview`             | `lib/src/core`, and the one module named below         |
| Sessions   | `lib/src/sessions`            | `lib/src/core`, `url_launcher`, `app_links`, `widgets` |
| Widgets    | `lib/src/widgets`             | Flutter, `webview_flutter`, the layers above           |
| Facade     | `lib/src/checkout.dart`       | `lib/src/platform.dart` only                           |

One module in `lib/src/webview` reaches a plugin, and it is the only one:
`external_link.dart` imports `url_launcher`. It is a single call wrapping a rule, its
launcher is injectable so the rule keeps its tests, and it stays there rather than in a
widget for that reason. `lib/src/platform.dart` is the one place that asks Flutter which
platform this is, so a test that overrides `debugDefaultTargetPlatformOverride` moves every
rule at once.

Keep that direction. A rule that moves out of `core` or `webview` and into a widget stops
being testable, and these are rules that fail silently on a phone.

## One source of truth per rule

Both presentations are different ways of showing the same checkout, so anything that decides
what a payment _means_ lives in one place and is shared:

| Rule                           | Where                                    | Used by                                            |
| ------------------------------ | ---------------------------------------- | -------------------------------------------------- |
| What a return link means       | `core/return_url.dart` → `resolveReturn` | the in-app handler and the browser session         |
| Where the checkout is drawn    | `core/presentation.dart`                 | `checkout.dart`                                    |
| What to do with a navigation   | `core/navigation.dart`                   | `webview/navigation_handler.dart`                  |
| What counts as the same scheme | `core/url.dart` → `normalizeScheme`      | `webview/app_schemes.dart`, `core/navigation.dart` |
| The web view settings          | `webview/platform_settings.dart`         | `widgets/getpayin_checkout_view.dart`              |
| One checkout at a time         | `core/session_guard.dart`                | `checkout.dart`                                    |
| Every text a payer can see     | `core/messages.dart`                     | both widgets and both session paths                |
| Settle-once                    | `core/deferred.dart`                     | the session host, the browser session              |

If you find yourself writing a second copy of one of these, that is the bug.

## Why the widgets are thin

`GetPayInCheckoutView` and `GetPayInProvider` hold almost no logic. What they would hold
lives in `webview/navigation_handler.dart` and `sessions/session_host.dart`, which are plain
classes with no widgets in them. That is what lets the suite cover the session lifecycle and
the navigation decisions in the Dart VM.

Three details in there are load-bearing, not style:

1. **The navigation handler belongs to one checkout.** It completes at most once, so it is
   rebuilt when `checkoutUrl`, `returnUrl` or `expectedInvoiceId` changes, and must _not_ be
   rebuilt on an ordinary rebuild, which would reset the latch and report one payment twice.
   The callbacks reach it through `widget`, which is always the current one.
2. **A failed load always shows the top bar.** Otherwise a checkout that cannot load with
   `headerShown: false` is a blank screen with no way out, the `open()` future never settles,
   and the session guard reports busy for the rest of the process.
3. **The wallet settings are applied before the page loads.** Android's Payment Request
   switch takes effect at the next load, so setting it afterwards gives the payer a checkout
   with no Google Pay button and nothing in the log.

## The payment sheet, and the two kinds of web view

The sheet (`lib/src/sheet`) takes the same payment through PayLink's hosted card fields. Its
decision-making is pure like everything else: `fields_session.dart` reads what `/init`
answered and decides whether a failure is fatal, `fields_protocol.dart` reads what the page
reports and turns a charge into a result, `fields_page.dart` writes the page. Only
`card_fields_controller.dart` and `wallet_surface.dart` touch a web view.

Those two are the reason an old invariant needed sharpening. "No scripts on the checkout web
view" was never about checkout pages; it is about **wallets**. WebKit turns Apple Pay off on
any page the host app has added scripts to, so the rule is:

| Surface                                      | Shows a wallet | Scripted by this package           |
| -------------------------------------------- | -------------- | ---------------------------------- |
| The hosted checkout (`GetPayInCheckoutView`) | yes            | never                              |
| The wallet surface (`WalletSurface`)         | yes            | never — it answers by navigating   |
| The card box (`CardFieldsController`)        | no             | yes: a channel and `runJavaScript` |

The card box is scripted deliberately. It shows card fields and nothing else, so there is no
wallet to lose, and the alternative — passing the client token through the page's URL — would
put a token that names a payment into the host's access log and the web view's history.

A test asserts the wallet surface has no channel and runs no script. Keep it that way.

## One claim of payment, two ways to make it

A return link and a hosted-fields charge are both a claim that an invoice was paid, read from
different artefacts. What a claim has to survive is decided once, in
`core/return_url.dart` → `settlePaidClaim`: only `PAID` is paid, and a paid claim for another
invoice is refused. `resolveReturn` feeds it a link; `resultFromPayment` feeds it a charge.
If you add a third source, feed it the same function.

## Two deep-link sources, one rule

`sessions/deep_link.dart` reads the return link from the two places `app_links` offers, and
neither is tied to a live checkout:

- The **link stream** is a push: each link is delivered once, as it happens. But a link that
  arrives before anything in Dart listens is held and replayed to the first listener.
- The **initial link** is a pull of state that persists. It answers with the first link the
  _process_ ever saw, whenever that arrived, and goes on answering with it.

So the watcher keeps one subscription for the whole process, opened by `prime()` as the
provider mounts; reads the initial link once, there; and tells a checkout only about links
that arrive while it is watching. A link that arrives with nothing waiting for it is dropped,
and refused if it turns up again.

Getting this wrong is not a style question: it is how a link that belongs to nothing becomes
the next checkout's `paid`.

## Differences from the Expo package

`@getpayin/expo-checkout` is the same checkout with the same rules. Where this one differs,
the platform forced it:

| Subject                 | Expo                                               | Flutter                                                                               |
| ----------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------- |
| The app's own schemes   | read from `app.json` via `expo-constants`          | declared by the app with `declareHostAppSchemes`: there is no app config to read      |
| The frame rule          | iOS only; Android does not report the frame        | both platforms: `webview_flutter` reports `isMainFrame` on each                       |
| The browser sheet       | `openAuthSessionAsync` reports its own dismissal   | `url_launcher` cannot, so the app's lifecycle does: `SheetDismissalDetector`          |
| Apple Pay               | `enableApplePay` on the web view                   | nothing to set; the promise is that no script is ever added                           |
| Google Pay              | `paymentRequestEnabled` prop                       | `AndroidWebViewController.setPaymentRequestEnabled`, plus `<queries>` in the manifest |
| "No invoice to bind to" | `undefined`; `null` is refused                     | `null`, which is also what a missing JSON field arrives as                            |
| Router help             | `createPaymentReturnRedirect` for `+native-intent` | `PaymentReturnRedirect` for `go_router`'s `redirect`                                  |
| The checkout screen     | a `Modal` above the tree                           | a full-screen route on the app's `Navigator`, so the back button closes it            |

## Testing

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

The suite runs in the Dart VM with every plugin replaced by something a test drives: the
browser session takes its ports as a value, the deep-link watcher takes its two sources as
functions, the external-link opener takes its launcher as an argument, and the widgets run
against a fake web view platform that reports navigations and page events on demand. So the
screen's own behaviour — presenting, completing once, failing closed with a way out — is
covered without a phone, which is unusual for a web view and is the reason the fake exists.

Every file carrying a rule is covered line for line. Two lines are exempt, both a plugin's
own constructor: `DeepLinkSource.platform` and the pair of `AndroidWebViewController` calls
that turn Google Pay on.

What the suite cannot cover is the phone itself. [`CONTRIBUTING.md`](../CONTRIBUTING.md)
lists the by-hand checks to run before a release.

## House style

1. **Doc comments on every declaration**, saying why the code is the way it is when the
   reason is not obvious from the name. `webview/platform_settings.dart` is the clearest
   example: each setting fails silently when wrong, so each one says what breaks.
2. **No comments inside function bodies.** A body that needs explaining wants a named helper
   or a doc comment, not a running commentary. A file-level block comment above the
   declarations is fine for the shape of a whole module.
3. `dart format` and `flutter analyze` settle the rest.
