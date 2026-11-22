# Troubleshooting

Most of what goes wrong here fails **silently**: the wallet button is simply absent, or the
payment completes and your app never hears about it. Nothing appears in the log. This page
is ordered by symptom.

## The payment works but my app never gets the result

1. **The return scheme does not match.** `options.returnUrl` must match the **Mobile App
   Return Scheme** on the integration, and that must match the `android:scheme` in your
   `AndroidManifest.xml` and the `CFBundleURLSchemes` entry in your `Info.plist`. All of
   them.
2. **The scheme is not declared natively at all.** Flutter has no app config that does this
   for you; see [Setup](setup.md#your-apps-scheme).
3. **You changed the manifest or `Info.plist` without rebuilding.** That is native
   configuration, so a hot restart will not pick it up.

## Payers land on an error page after paying

Your router is treating the return link as a route. Add the `go_router` redirect from
[Setup](setup.md#go_router).

## The checkout answers HTTP 403

The link's signature no longer matches what was signed.

1. **You passed `checkoutUrl` through a route parameter.** A router decodes it a second
   time. Keep it in memory and hand it straight to `open()`.
2. **The order title contains unusual characters.** Characters such as `(`, `)` and `'` in
   `order_title` can break the signature. Keep titles to letters, numbers and spaces, and
   check with GetPayIn support whether the backend fix for this has shipped.

## No Apple Pay button on iPhone

1. **Something added a script to the page.** WebKit turns Apple Pay off on any page the host
   app has added scripts to. If you wrapped the checkout in a web view of your own, remove
   every JavaScript channel and every `runJavaScript` call. Use `GetPayInCheckoutView` as it
   is.
2. **The device has no card in Wallet**, or you are on a simulator without one.
3. **Apple Pay is not enabled on the GetPayIn company.** Ask support.

## No Google Pay button on Android

In the app's own screen (`googlePayInApp: true`):

1. **The three `<queries>` entries are missing from `AndroidManifest.xml`.** Android's
   WebView then cannot find the payment apps on the phone. See [Setup](setup.md#android).
2. **Google has not approved your app yet.** Set `googlePayInApp: false` until it has.
   Google Pay then works in the browser sheet with no approval. See
   [Google Pay on Android](google-pay.md).
3. **Android System WebView is older than 137**, or **Google Play services older than
   25.18.30**.
4. **Something overrode the user agent.** Google checks it and requires it to end with
   `GOOGLE_PAY_SUPPORTED`. Do not set a user agent on the web view.

In the browser sheet (`googlePayInApp: false`): the payer has no card in Google Pay, or the
sheet opened in a browser without Google Pay support.

## A blank white checkout screen

The page could not load. The provider shows the message and a close button; if you render
`GetPayInCheckoutView` yourself, handle `onLoadError` or you get a blank screen with no way
out.

Check that the `checkoutUrl` your server returned is reachable from the device, and that the
link has not expired. The `detail` argument to `onLoadError` names the cause; the provider
writes it with `debugPrint`, prefixed `GetPayIn checkout:`.

## `GetPayInProviderMissingError`

An in-app checkout was opened with no `GetPayInProvider` mounted above it. Mount it under
your app. Note that iOS always uses the in-app screen, so an app that only ever tested the
Android browser sheet will hit this the first time it runs on an iPhone.

The message tells you which of the two it is. "found no Navigator" means the provider is
mounted, but above your app's `Navigator` — in `MaterialApp.builder`, or in a router shell.
Give it the `navigatorKey` you pass to `MaterialApp`; see [Setup](setup.md#the-provider).

## `GetPayInSessionBusyError`

Another checkout is still open, almost always a double tap on Pay. Guard the button with
`GetPayInCheckout.busy`, or catch and ignore it.

## A real payment came back as `cancelled`

The app came back to the front and no return link followed within the grace period. Check
that the return scheme matches everywhere, as above: without the native declaration the deep
link never reaches the app at all, and dismissing the sheet looks exactly like closing it.
Your server's `invoice.paid` webhook is the authority here, and it will have fired.

## A browser-sheet checkout never finishes

`open()` stays pending when the sheet goes away without the app reporting that it is back in
front and without the return link arriving. That is the one case the browser presentation
cannot see, and it is why `presentation: CheckoutPresentation.browser` is for diagnostics
rather than for production on iOS, where the platform rule uses the in-app screen anyway.

## A result came back as `notPaid` with a message about a different invoice

`expectedInvoiceId` did its job: the return link named an invoice other than the one this
checkout was opened for. Either something forged the link, or your code passed the wrong
`expectedInvoiceId`. Check which invoice your server actually created.

## A 3-D Secure bank app does not open

The package opens the bank's link directly, with no scheme to declare. If nothing opens, the
bank's app is most likely not installed on that phone. The payer is shown
`linkErrorMessage` and the top bar appears so they can close the checkout; they can finish
the step on the bank's web page if it offers one.

On Android, some bank pages use `intent://` links. `url_launcher` hands those to the system
as an ordinary view intent rather than parsing them the way Chrome does, so a step that
works in the browser sheet may do nothing in your app's own screen. If you hit one, please
report it with the bank's name.

The package deliberately refuses some links rather than handing them to the phone:

1. Script schemes: `javascript:`, `vbscript:`.
2. Your own app's schemes, when the link is not the return link. That is every scheme you
   passed to `declareHostAppSchemes`, not only the return link's. See
   [Security model](security.md).
3. Schemes with no part in paying: `market:`, `itms-apps:`, `itms-services:`, `sms:`,
   `smsto:`, `mms:`, `shortcuts:`, `content:`, `android-app:`.
4. Anything a frame inside the checkout page asks for, other than ordinary web content.

`tel:`, `mailto:` and `intent:` are allowed. If a legitimate flow needs one of the refused
ones, it is a bug, so please report it with the bank's name.

## Reporting a bug

Include the package version, the phone and OS version, the output of `flutter doctor`, which
presentation was used (`GetPayInCheckout.presentationFor()` tells you), and the
`CheckoutResult` you received. Never include real card numbers or live credentials.

For a suspected vulnerability, report privately. See [`SECURITY.md`](../SECURITY.md).
