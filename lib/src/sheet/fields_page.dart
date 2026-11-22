import 'dart:convert';

/// The channel the fields page posts its events on.
const String fieldsChannelName = 'PayLinkFields';

/// Builds the page that hosts PayLink's card fields.
///
/// **You host this file yourself**, on the origin registered on your integration, over
/// HTTPS. That is not a formality: the origin is baked into the capture context CyberSource
/// issues and checked on every call, so fields served from anywhere else render nothing at
/// all. The sheet loads this page into a web view and drives it over [fieldsChannelName].
///
/// The page is deliberately inert until it is told to start. In the sheet it waits for the
/// host to hand it a client token over the channel, so the token never reaches the page's
/// URL — and so never reaches your access log, the web view's history, or a `Referer`
/// header. The wallet surface has no channel (a web view the host has scripted cannot show
/// Apple Pay), so there the token arrives in the fragment, which browsers do not send.
///
/// Everything it does, it does through PayLink: the SDK comes from [sdkUrl], the capture
/// context, payer authentication and the charge are PayLink's endpoints, and the card
/// iframes are the gateway's own. Nothing here talks to a gateway directly.
String buildFieldsPageHtml(
    {required String sdkUrl, String channel = fieldsChannelName}) {
  final script = jsonEncode(sdkUrl);
  final channelName = jsonEncode(channel);

  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Card</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: transparent; }
  body {
    font: 16px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    color: #30313d;
    -webkit-text-size-adjust: 100%;
  }
  #box { border: 1px solid var(--border, #e6e6e6); border-radius: 8px; overflow: hidden; background: #fff; }
  #box.invalid { border-color: var(--danger, #df1b41); }
  .row { display: flex; }
  .cell { position: relative; flex: 1; height: var(--rowHeight, 56px); padding: 0 12px; display: flex; align-items: center; }
  .cell + .cell { border-left: 1px solid var(--border, #e6e6e6); }
  .row + .row { border-top: 1px solid var(--border, #e6e6e6); }
  .cell > div, .cell > input { width: 100%; height: 100%; }
  input {
    border: 0; outline: 0; background: transparent; font: inherit; color: inherit;
    padding: 0; min-width: 0;
  }
  input::placeholder { color: var(--placeholder, #a3acb9); }
  .marks {
    position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
    display: flex; gap: 4px; pointer-events: none;
  }
  .mark {
    width: 32px; height: 22px; border-radius: 4px; background: #f1f1f3;
    color: #30313d; font-size: 8px; font-weight: 700; line-height: 22px;
    text-align: center; letter-spacing: 0.2px;
  }
  .mark[hidden] { display: none; }
  /* The gateway's wallet widget renders its own launchers at its own size. These are the
     same rules PayLink's own checkout puts around it, so the button is one row of this
     form rather than a panel sitting on top of one. */
  /* PayLink's SDK writes this row, wording and all, so that it can evidence what the payer
     agreed to. The page says where it sits and what it is drawn with, never what it says. */
  #consent { min-height: var(--rowHeight, 56px); display: flex; align-items: center; }
  #consent[hidden] { display: none; }
  #consent [data-paylink-consent-row] {
    display: flex; align-items: center; gap: 10px; width: 100%;
    font-size: 14px; color: var(--text, #30313d);
  }
  #consent [data-paylink-consent] { width: 18px; height: 18px; accent-color: var(--accent, #0570de); }

  #wallet { min-height: var(--rowHeight, 56px); }
  #wallet .app { display: flex; flex: 1; gap: 12px; align-items: stretch; }
  #wallet .app > * { flex: 1 1 0; min-width: 0; width: auto; margin: 0; }
  #wallet .launcher-googlepay { height: var(--rowHeight, 56px); border: 0; }
  #wallet apple-pay-button {
    --apple-pay-button-width: 100%;
    --apple-pay-button-height: var(--rowHeight, 56px);
    --apple-pay-button-border-radius: var(--radius, 8px);
    width: 100%;
  }
</style>
</head>
<body>
  <div id="card">
    <div id="box">
      <div class="row" id="name-row" hidden><div class="cell"><input id="name" autocomplete="cc-name" aria-label="Name on card"></div></div>
      <div class="row"><div class="cell"><div id="number"></div><span class="marks" id="marks"><span class="mark" data-brand="visa">VISA</span><span class="mark" data-brand="mastercard">MC</span><span class="mark" data-brand="amex">AMEX</span><span class="mark" data-brand="unionpay">UP</span></span></div></div>
      <div class="row">
        <div class="cell"><input id="expiry" inputmode="numeric" autocomplete="cc-exp" aria-label="Expiry"></div>
        <div class="cell"><div id="cvc"></div><span class="marks"><span class="mark">CVC</span></span></div>
      </div>
    </div>
  </div>
  <div id="consent" hidden></div>
  <div id="wallet" hidden></div>

<script src=$script></script>
<script>
(function () {
  var CHANNEL = $channelName;
  var fields = null;
  var started = false;

  function post(message) {
    var channel = window[CHANNEL];

    if (channel && typeof channel.postMessage === 'function') {
      channel.postMessage(JSON.stringify(message));
    }
  }

  function fail(error) {
    post({
      type: 'error',
      code: (error && error.code) || 'unknown',
      message: (error && error.message) || 'The card could not be taken.'
    });
  }

  function applyStyle(style) {
    if (!style) { return; }

    Object.keys(style).forEach(function (name) {
      document.documentElement.style.setProperty('--' + name, style[name]);
    });
  }

  function expiry() {
    var parts = String(document.getElementById('expiry').value || '').split('/');
    var year = (parts[1] || '').trim();

    return {
      expirationMonth: (parts[0] || '').trim(),
      expirationYear: year.length === 2 ? String(2000 + Number(year)) : year
    };
  }

  function formatExpiry(raw) {
    var digits = String(raw || '').replace(/[^0-9]/g, '').slice(0, 4);

    return digits.length < 3 ? digits : digits.slice(0, 2) + ' / ' + digits.slice(2);
  }

  /**
   * True while the card is still in date. The last moment it is good for is the end of the
   * month printed on it, so the first of the next month is the comparison.
   */
  function expiryValid(parts) {
    var month = Number(parts.expirationMonth);
    var year = Number(parts.expirationYear);

    if (!(month >= 1 && month <= 12) || !(year >= 2000)) { return false; }

    return new Date(year, month, 1) > new Date();
  }

  /**
   * The name is reported rather than judged: what counts as a name the charge can be billed
   * to is the host's rule, and the page would only be a second place to keep it.
   */
  function watchName(label) {
    var input = document.getElementById('name');

    input.placeholder = label || 'Name on card';
    document.getElementById('name-row').hidden = false;

    input.addEventListener('input', function () {
      post({
        type: 'change',
        field: 'name',
        empty: input.value.trim().length === 0,
        value: input.value,
        couldBeValid: true
      });
    });
  }

  function watchExpiry(label) {
    var input = document.getElementById('expiry');

    input.placeholder = label || 'MM / YY';

    input.addEventListener('input', function () {
      input.value = formatExpiry(input.value);

      post({
        type: 'change',
        field: 'expiry',
        valid: expiryValid(expiry()),
        empty: input.value.length === 0,
        couldBeValid: true
      });
    });
  }

  /**
   * Shows the networks a card could still be on, narrowing to one as the gateway decides.
   *
   * The number itself is rendered by the gateway in its own frame, so these sit beside it
   * in the page's own markup and take no pointer events: a tap anywhere in the row still
   * belongs to the field.
   */
  function showBrands(state) {
    var detected = (state && state.card) || [];
    var named = detected.length === 1 ? String(detected[0].name || '') : '';
    var marks = document.querySelectorAll('#marks .mark');

    for (var index = 0; index < marks.length; index++) {
      marks[index].hidden = named !== '' && marks[index].dataset.brand !== named;
    }
  }

  function listen(instance, walletMode) {
    instance.on('change', function (event) {
      var state = event.state || {};

      if (event.field === 'number') { showBrands(state); }

      post({
        type: 'change',
        field: event.field,
        valid: !!state.valid,
        empty: !!state.empty,
        couldBeValid: state.couldBeValid !== false
      });
    });
    instance.on('authenticating', function (event) {
      post({ type: 'authenticating', stage: (event && event.stage) || 'setup' });
    });
    instance.on('charging', function () { post({ type: 'charging' }); });
    instance.on('walletready', function (event) {
      post({ type: 'walletready', paymentTypes: (event && event.paymentTypes) || [] });
    });
    instance.on('walleterror', function (event) {
      post({ type: 'walleterror', message: event && event.message });
    });
    instance.on('error', fail);

    if (walletMode) { relayWalletOutcome(instance); }
  }

  /**
   * A wallet payer never calls pay(), so the outcome arrives as an event. With no channel to
   * answer on, the page does what a browser would: it goes to the return link, which the
   * host reads off the navigation.
   */
  function relayWalletOutcome(instance) {
    function go(result) {
      if (result && result.returnUrl) { window.location.href = result.returnUrl; }
    }

    instance.on('success', go);
    instance.on('declined', go);
  }

  function start(config, walletMode) {
    if (started) { return; }

    started = true;
    applyStyle(config.style);

    var wallets = config.wallets || [];
    var options = {
      clientToken: config.clientToken,
      number: '#number',
      securityCode: '#cvc',
      numberOptions: { placeholder: config.cardNumberLabel || 'Card number' },
      securityCodeOptions: { placeholder: config.securityCodeLabel || 'CVC' },
      styles: config.fieldStyles || {
        input: { 'font-size': '16px', 'font-family': 'inherit', color: '#30313d' },
        '::placeholder': { color: '#a3acb9' },
        invalid: { color: '#df1b41' }
      }
    };

    if (config.collectConsent) {
      options.consent = '#consent';
      document.getElementById('consent').hidden = false;
    }

    if (wallets.length > 0) {
      options.wallets = wallets;
      options.wallet = '#wallet';
      document.getElementById('wallet').hidden = false;
    }

    if (walletMode) {
      document.getElementById('card').hidden = true;
    }

    try {
      fields = PayLink.fields(options);
    } catch (error) {
      fail(error);
      return;
    }

    listen(fields, walletMode);
    watchExpiry(config.expiryLabel);

    if (config.collectName) { watchName(config.nameLabel); }

    fields.mount().then(function (ready) {
      post({ type: 'ready', amountMinor: ready.amountMinor, currency: ready.currency });
    }).catch(fail);
  }

  window.__paylinkHost = {
    start: function (config) { start(config || {}, false); },
    pay: function (options) {
      if (!fields) { return; }

      var asked = options || {};
      var parts = expiry();

      if (asked.billing) { parts.billing = asked.billing; }
      if (asked.tokenize) { parts.tokenize = true; }

      fields.pay(parts).then(function (result) {
        post({
          type: 'payment',
          success: !!result.success,
          message: result.message,
          reasonCode: result.reasonCode,
          invoiceId: result.invoiceId,
          paidStatus: result.paidStatus,
          returnUrl: result.returnUrl
        });
      }).catch(fail);
    },
    destroy: function () {
      if (fields) { fields.destroy(); fields = null; started = false; }
    }
  };

  /**
   * The wallet surface carries its configuration in the fragment, because a web view the
   * host has scripted cannot show Apple Pay, so there is no channel to hand it over. The
   * card surface has one, and waits to be told.
   */
  function startFromFragment() {
    var hash = new URLSearchParams(String(window.location.hash || '').replace(/^#/, ''));
    var token = hash.get('t');

    if (!token) { return; }

    start({
      clientToken: token,
      wallets: (hash.get('w') || '').split(',').filter(Boolean),
      style: {}
    }, true);
  }

  startFromFragment();
})();
</script>
</body>
</html>
''';
}

/// The URL the wallet surface is loaded with.
///
/// The client token travels in the fragment: a browser never sends it to the server, so it
/// stays out of the host's access log, and it is spent on one payment within the hour.
String walletPageUrl({
  required String pageUrl,
  required String clientToken,
  required List<String> wallets,
}) {
  final base = pageUrl.split('#').first;
  final query = <String>[
    't=${Uri.encodeQueryComponent(clientToken)}',
    if (wallets.isNotEmpty) 'w=${Uri.encodeQueryComponent(wallets.join(','))}',
  ].join('&');

  return '$base#$query';
}
