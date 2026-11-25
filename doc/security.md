# Security model

What the package guarantees, what it cannot, and where your server has to take over. To
report a vulnerability, see [`SECURITY.md`](../SECURITY.md).

## What never enters the app

1. **No signing secret.** Your hash token belongs on your server, which signs
   `POST /api/integration/init` and hands the app only a `checkout_url`. The package
   contains no HMAC and no reference to a hash token.
2. **No card details.** The payer enters them on the hosted checkout, inside CyberSource's
   own frames. The package adds no script to that page, so it has no way to read them even
   in principle.
3. **No storage.** The package persists nothing.

## The return link is attacker-controllable

This is the important one.

Your app's return scheme is declared in your `Info.plist` and your `AndroidManifest.xml`.
It is public. **Anything on the phone can open your app with it**: a link in a web page, an
SMS, a QR code, or `startActivity` from any other installed app, carrying whatever query it
likes:

```text
myapp://payment-return?success=1&invoice_id=whatever-the-attacker-wants
```

So `CheckoutStatus.paid` means "the link said so", not "the money moved".

### What the package does about it

1. **An unreadable status is never upgraded.** A link whose status the reader does not
   recognise becomes `notPaid`, with a message saying so. No code path turns absent or
   unknown input into `paid`.
2. **A checkout is settled only by a link that arrives while it is watching.** The package
   listens for deep links once, as `GetPayInProvider` mounts, and drops every link that
   reaches the app with no checkout waiting for one. So the link your app was opened with
   cannot become the result of the next payment the payer starts, and neither can the link
   that settled the payment before it. Both are links the plugin can still hand back after
   the fact, which is why the rule lives here rather than in it.
3. **`expectedInvoiceId` binds the link to the checkout.** With it set, a paid link naming a
   different invoice, or naming none at all, is reported as `notPaid`. **Pass it whenever
   you have it.** Without it the package has nothing to tie the link to.
4. **One checkout at a time**, so a second cannot be stacked over a live one.
5. **A result is delivered once.** The return link can arrive from a web view navigation, a
   deep-link event and a recreated activity at the same moment; every settle after the first
   is dropped, so one payment cannot be reported twice.

### What your server must do

Confirm the `invoice.paid` webhook before you deliver anything. None of the above is a
substitute.

Treat the client result as a cue for what to show the payer, never as the authority for what
they are owed.

## The web view

Every navigation goes through the package's own handler, which sorts them into four
outcomes:

| Outcome          | What happens           | Examples                                                                            |
| ---------------- | ---------------------- | ----------------------------------------------------------------------------------- |
| `endCheckout`    | The checkout ends.     | your return link, navigating the whole page                                         |
| `load`           | Stays in the web view. | `https:`, `http:`, `about:`, `data:`, `blob:`, `file:`                              |
| `openExternally` | Handed to the phone.   | a bank app for 3-D Secure, `tel:`, `mailto:`, `intent:`                             |
| `block`          | Refused.               | `javascript:`, your own app's schemes, `market:`, `sms:`, a frame navigating itself |

Three of those deserve explanation.

**Why `openExternally` exists, and why it is narrowed.** A 3-D Secure step can hand the
payer to their bank's app, and every acquirer has a different set of bank schemes, so this
cannot be an allow-list inside the package. It is narrowed in three ways instead:

1. Script schemes (`javascript:`, `vbscript:`) are refused.
2. **Every scheme your own app answers to is refused whenever it is not the return link**:
   the return link's own scheme, plus everything you passed to `declareHostAppSchemes`. So a
   page cannot drive your app's deep-link routes.
3. Schemes with no part in paying for anything are refused even though another app may
   answer to them: `market:`, `itms-apps:`, `itms-services:`, `sms:`, `smsto:`, `mms:`,
   `shortcuts:`, `content:` and `android-app:`. A browser would refuse most of these from
   the same page, and the link here is opened with no confirmation of any kind.

Anything else is launched directly.

That is a trade-off. Asking `canLaunchUrl` first would limit pages to the schemes your app
has declared in `LSApplicationQueriesSchemes` or `<queries>`. In practice that is none, so a
bank-app step would never open. Without it, a page inside the checkout can open another
installed app without a tap, which is exactly what a bank-app step needs. A link nothing on
the phone can open is reported through `onLoadError`, so the payer is told why the step did
nothing and still has a way out.

Because `declareHostAppSchemes` is the only thing standing between a checkout page and your
own deep-link routes, declare all of them. The Expo package reads them from `app.json`; here
it is a call you make.

**Why a frame inside the page gets less.** A frame navigating *itself* can only ever `load`
ordinary web content. It never ends the checkout and never reaches another app. The reason
is that a 3-D Secure page knows the invoice id it is authenticating, so a frame allowed to
end the checkout could report a payment that was never made, and `expectedInvoiceId` would
not catch it, because the invoice id is genuine.

The flag the web views report, `isMainFrame`, names the frame **being navigated**, not the
frame that asked for it — no web view reports the latter. A navigation of the whole page is
therefore judged as one wherever it came from. That is the limit of the rule, and it is why
the rule is one layer of several rather than the thing you rely on.

Unlike the Expo package, it holds on **both** platforms: `webview_flutter` reports the flag
on Android as well as iOS. That is one fewer gap, not a reason to trust the app's result:
the `invoice.paid` webhook on your server still decides whether you deliver.

The reason this matters: a 3-D Secure page is hosted by the **issuer**, not by GetPayIn. The
page driving these navigations is not one this package controls.

**Why nothing is injected.** WebKit turns Apple Pay off on any page the host app has added
scripts to. So the checkout web view registers no JavaScript channel and is never asked to
run JavaScript — not for diagnostics, and not on Android either.

## The payment sheet

The sheet adds one credential and one surface, and neither changes the rule above.

**The client token is designed to live on a device.** PayLink mints it on `/init`, it is
encrypted, it lasts 60 minutes and it names exactly one payment. It cannot create a payment,
refund, void or read anything back — everything your hash token can do, it cannot. The hash
token stays on your server and signs `/init` and nothing else.

The token is handed to the card page over the channel once the page has loaded, never in the
page's URL: a URL reaches the host's access log, the web view's history and any `Referer` the
page sends. The wallet surface is the exception — a page the host has scripted cannot show
Apple Pay, so there is no channel to hand it over, and the token travels in the fragment,
which a browser does not send to a server.

**The card never reaches your app.** The number and security code are rendered by the gateway
in iframes on the page you host. What the page hands back is a one-time transient token.

**The origin is checked on every call** and is baked into the capture context, which is why
the page has to be served from the origin registered on your integration. The sheet refuses
to load a page from anywhere else rather than showing an empty box.

**A charge is idempotent per invoice.** PayLink holds it behind a per-payment lock, so a
double-tapped pay button is refused with `in_progress` rather than charged twice.

**The card box answers one charge: its own.** The box is the one surface the package
scripts, and the channel its page posts on is shared with everything that page frames — the
gateway's own fields, and the issuer's 3-D Secure step. Neither platform tells the host
which frame sent a message. So the sheet reports a payment only while it is waiting for the
answer to a charge it started, and only your registered origin may hold the box's top frame;
a frame inside it may still load, because that is how all three are rendered.

## Saving a card

A vaulted card's token never travels through the app. The app-return bridge builds exactly
`success`, `invoice_id`, `invoice_status`, `message` and `signature` — there is no
`card_token` on it, and a token that unlocks a stored card has no business on a public app
scheme that anything on the phone can invoke.

It reaches your server on the `card_token.created` webhook, and charging it is a call your
server signs with your hash token. So a stolen return link cannot save a card, cannot read
one, and cannot spend one.

The verification run itself is a real authorization — one unit of currency, released
straight away — which is why `GetPayInCheckout.saveCard` reads the link as a save rather
than as a payment, and why a save still has to be confirmed on your server before you show
the payer a card they can use.

## Reading the return link

The link is read by exact field name (`success`, `invoice_id`, `invoice_status`, `message`),
and the values are taken as sent. A link is refused outright when it repeats any field, or
carries a name only a looser reader would take for one of those four (`Success`,
`invoiceId`, `%73uccess`).

That keeps this reader and a server checking the link's `signature` from ever reading
different values out of one link. A reader that folded case or took the first copy of a field
could report invoice B as paid from a link whose signature is genuine for invoice A:
`?invoiceId=5001&success=1&invoice_id=4000` is a real signed link for 4000 that a looser
reader calls 5001.

A refused link is `notPaid` with `CheckoutResultCode.unreadableReturnLink`. A genuine
decline carries no code, which is how the two are told apart. The link's own message would
not, because GetPayIn always sends one.

## What is out of scope

1. **Forging the exact return link.** An attacker who opens your app with a correctly shaped
   link naming the right invoice at the right moment can make the app *display* a success.
   They cannot make your server believe it. This is why the webhook check is not optional.
2. **A compromised device.** Root, a malicious keyboard, screen recording. Nothing a payment
   SDK does survives that.
3. **Your own deep-link routes.** The package refuses to hand your scheme back to the OS
   from the checkout, but your app's routes should validate their own input regardless.

## Checklist

- [ ] The hash token is on your server only: not in the app, not in version control, not in
      any client-side config.
- [ ] Your server confirms `invoice.paid`, with `success` and status `PAID`, before
      fulfilling.
- [ ] `expectedInvoiceId` is passed on every `open()` call, and is never null when your
      server returned an invoice id.
- [ ] `declareHostAppSchemes` lists every scheme your app answers to.
- [ ] The Mobile App Return Scheme is specific to your app.
- [ ] You have added no scripts to the checkout view.
