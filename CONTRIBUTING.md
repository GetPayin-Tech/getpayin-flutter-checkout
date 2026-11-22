# Contributing

Thanks for helping with `getpayin_flutter_checkout`.

## Getting set up

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
npx markdownlint-cli@0.50.0 '**/*.md'
```

A green run of those five is a green pipeline: `.github/workflows/verify.yml` runs the same
ones, plus the coverage gate and `flutter pub publish --dry-run`.

`dart format` is the authority on layout, which is why `require_trailing_commas` is not
enabled: the two disagree, and a lint that fights the formatter is a lint that loses.

## Read this first

[`doc/architecture.md`](doc/architecture.md) explains how the package is laid out, which
layer may import what, why the widgets are deliberately thin, and why the two deep-link
sources are treated differently. Changing anything in `lib/src/core`, `lib/src/webview` or
`lib/src/sessions` without reading it is how a silent payment bug gets in.

[`doc/security.md`](doc/security.md) explains the threat model the code is written
against, above all that the return link is attacker-controllable.

## Things that must never change

These are not style preferences. Each one has cost someone a working wallet or a leaked
secret:

1. No signing and no hash token in the app. The client's server signs
   `POST /api/integration/init` and hands the app only a `checkout_url`.
2. No JavaScript channel and no `runJavaScript` on any surface that can show a wallet —
   the hosted checkout and the wallet surface. WebKit turns Apple Pay off on any page the
   host app has added scripts to, with no error. The payment sheet's card box is scripted
   on purpose and shows no wallet; a test asserts the wallet surface stays unscripted.
3. No user-agent override. Google checks it and requires it to end with
   `GOOGLE_PAY_SUPPORTED`.
4. The app never treats the return link as proof of payment. A link the reader cannot
   understand is reported as `notPaid`, never paid.
5. The checkout's `iframe` mode is never used. It needs the integration's registered website
   as the page around it, and an app screen has none.
6. A script scheme never reaches the launcher, and neither does one of the app's own
   schemes. `openExternally` hands a URL to the phone and the page is what chose it.
7. The link the app was launched with never settles a checkout opened afterwards.
8. Android's Payment Request switch is set before the page loads, never after.

## Tests

Add a test with every behaviour change. The suite needs no phone and no emulator: every
plugin is replaced by something the test drives.

| Plugin                          | Replaced by                                                                                        |
| ------------------------------- | -------------------------------------------------------------------------------------------------- |
| `webview_flutter`               | `test/support/fake_webview.dart`, which reports navigations, page events and HTTP errors on demand |
| `url_launcher`                  | `test/support/fake_launcher.dart`, which records the mode each link was launched with              |
| `app_links`                     | `DeepLinkSource`, which takes its two sources as functions                                         |
| the browser sheet's whole flow  | `BrowserCheckoutPorts`, which takes the open, close and two watchers as values                     |

Every file carrying a rule is covered line for line, and the gate in CI keeps it that way.
Two lines are exempt, both of them a plugin's own constructor: `DeepLinkSource.platform`
and the pair of `AndroidWebViewController` calls that turn Google Pay on. Those are what
the by-hand checks below are for.

When you fix a bug, write the test that fails first. Several of the tests here exist because
they caught a real one: `test/launch_url_test.dart` and `test/return_url_spoofing_test.dart`
in particular.

What the suite cannot cover is the phone. Before a release, check by hand:

1. On an iPhone build: Apple Pay pays in the app's own screen and the app gets `paid`. Card
   with a 3-D Secure bank step works. Closing the screen gives `cancelled`.
2. On an Android build Google has approved, with `googlePayInApp: true`: Google Pay pays in
   the app's own screen.
3. On an Android build without approval, with `googlePayInApp: false`: the checkout opens in
   the browser sheet, Google Pay pays, and the app gets the result back. Dismissing the
   sheet without paying gives `cancelled`.
4. The system back button on Android closes the in-app checkout and gives `cancelled`.

## Documentation

The docs are split by job, and a change usually touches one of them:

| File                      | For                                                               |
| ------------------------- | ----------------------------------------------------------------- |
| `README.md`               | What it is, install, a quick start, and links out. Keep it short. |
| `doc/setup.md`            | Prerequisites and the native configuration.                       |
| `doc/taking-payments.md`  | The day-to-day integration.                                       |
| `doc/google-pay.md`       | The Android approval flow.                                        |
| `doc/api.md`              | Every export. Update it whenever the public surface changes.      |
| `doc/security.md`         | The threat model.                                                 |
| `doc/troubleshooting.md`  | Symptom-first. Add to it whenever you learn a new silent failure. |
| `doc/architecture.md`     | For contributors, including what differs from the Expo package.   |

## Commits and pull requests

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`). Say what breaks if the change is
wrong. That is the part a reviewer cannot work out from the diff.

## Releasing

1. Update `CHANGELOG.md`.
2. Bump the version in `pubspec.yaml`.
3. Tag `vX.Y.Z`, then `dart pub publish`.
