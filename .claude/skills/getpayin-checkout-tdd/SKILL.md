---
name: getpayin-checkout-tdd
description: Write tests first for the getpayin_checkout Flutter package, red then green then refactor, with the fakes that stand in for every plugin. Use when adding a test, fixing a bug, or changing behaviour anywhere under lib/, when the user says TDD, test-first, red green refactor, "write a test", "cover this", or "write the failing test first", and when deciding where a test belongs or why a widget test hangs, never settles, or fails only in the full suite.
---

# Test-first in getpayin_checkout

Every behaviour change starts with a test that fails for the right reason. The suite needs
no phone: every plugin is replaced by something the test drives, so there is no excuse for
writing the code first.

## The loop

1. **Write the test.** Name it as a sentence about behaviour, not about the method:
   `'keeps the sheet open on a decline, with the reason'`, never `'test _settle'`.
2. **Watch it fail, and read the failure.** It has to fail because the behaviour is missing,
   not because the file does not compile or a fake is unwired. A compile error is not red.

   ```bash
   flutter test test/payment_sheet_test.dart --plain-name 'keeps the sheet open'
   ```

3. **Write the smallest change that passes.** Not the general case, not the refactor.
4. **Run the file, then the suite.** A fix that greens one file and reddens another is not
   done.
5. **Refactor with the suite green**, then `dart format .` and `flutter analyze`.
6. **Check the rule is covered.** A new rule in `core`, `webview`, `sessions` or `sheet` is
   covered line for line, and CI fails on anything less.

   ```bash
   flutter test --coverage
   ```

## Where the test goes

| What changed                          | Where it is tested                      | How                                              |
| ------------------------------------- | --------------------------------------- | ------------------------------------------------ |
| A rule in `lib/src/core`              | `test/<rule>_test.dart`                 | Plain Dart. No widgets, no fakes.                |
| A session flow                        | `test/browser_session_test.dart`        | `FakePhone` as `BrowserCheckoutPorts`            |
| The deep-link ordering                | `test/launch_url_test.dart`             | `FakeDeepLinks` as a `DeepLinkSource`            |
| A web view behaviour                  | `test/checkout_screen_test.dart`        | `FakeWebViewPlatform`                            |
| The payment sheet                     | `test/payment_sheet_test.dart`          | `FakeWebViewPlatform` + `FakeUrlLauncher`        |
| A call that reaches a plugin directly | `test/platform_ports_test.dart`         | the platform-interface fakes                     |

## The fakes

```dart
final webView = FakeWebViewPlatform.install();   // every web view the app opens
final launcher = FakeUrlLauncher.install();      // every link and browser sheet
returnLinkWatcher = ReturnLinkWatcher(source: FakeDeepLinks().source);
```

- `webView.controllers` is every page in creation order. Find one by what it loaded rather
  than by index when more than one is open.
- `controller.post(json)` is the page's own script talking to the host.
- `controller.finishLoading()` fires `onPageFinished`, which is what makes the host send the
  page its client token.
- `controller.scripts` is every `runJavaScript` the host ran, and `controller.channels` every
  channel it registered. **The wallet surface must have neither**; there is a test that says
  so, and Apple Pay depends on it.
- `FakePhone` drives a browser checkout: `deliver(link)`, `dismiss()`, and `openFailure` for
  a phone with no browser.

## Gotchas that have cost an afternoon here

1. **`pumpAndSettle` never returns.** The checkout draws an indeterminate progress
   indicator, which never settles. Pump fixed frames instead:

   ```dart
   await tester.pump();
   await tester.pump(const Duration(seconds: 1));
   await tester.pump();
   ```

2. **Choose the presentation per checkout, not with the global override.** A widget test
   verifies its invariants *before* its own `tearDown`, so a
   `debugDefaultTargetPlatformOverride` reset there arrives too late and fails the test.
   Pass `presentation: CheckoutPresentation.inApp` in the options.
3. **A controller builds its page when it is constructed, not when it is rendered.** If the
   test needs the page loaded, call `finishLoading()` on that controller first.
4. **Equality by value needs a local.** `expect(<T>[a, b].toSet(), hasLength(1))` trips
   `prefer_collection_literals`, and the literal form trips `equal_elements_in_set`. Assign
   the list to a variable first.
5. **Global state is shared between tests.** `declareHostAppSchemes`, `returnLinkWatcher`,
   `browserCheckoutPorts` and the presenter registry all persist: set them in `setUp` and
   clear them in `tearDown`.

## When fixing a bug

Write the failing test first, and say in its name what the bug was. Two tests here exist
because they caught real ones, and both read as statements about behaviour:

- `test/launch_url_test.dart`: a forged link that cold-starts the app must never settle the
  next checkout.
- `test/return_url_spoofing_test.dart`: a link that merely looks like the return link must
  not pass as one.

A test that would still pass with the bug reintroduced is not a regression test. Revert the
fix, watch it fail, put the fix back.

## What not to test

- The widgets' pixels. Test what the payer can do, not what it looks like.
- A plugin's own behaviour. The fakes stop at the boundary; the device checks in
  `CONTRIBUTING.md` cover the rest.
- Anything already covered by a rule's own test. A widget test that re-asserts
  `resolveReturn` is a slower copy of a faster test.
