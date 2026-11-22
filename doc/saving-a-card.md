# Saving a card

Vault a card so the payer does not have to enter it again. The run is hosted, like a
checkout, and it ends with a token — on your server, never in the app.

## What a card save actually is

```text
your server  ──▶  POST /v2/integration/tokens/init        creates the run
             ◀──  tokenization_url
your app     ──▶  GetPayInCheckout.saveCard(url, …)       payer enters the card
                  └─ one unit of currency is authorized, to prove the card is live
                  └─ the card is vaulted
                  └─ the authorization is released
your app     ◀──  CardSaveResult                          saved | notSaved | cancelled
your server  ◀──  card_token.created webhook              the token, and the real answer
```

The verification leaves its invoice **unpaid on purpose**. That is why a save has its own
call and its own result: read with the payment rules, every successful save would come back
as `notPaid`, because the invoice is `VOIDED` rather than `PAID`.

## Taking one

`startCardSave` is your server calling `/tokens/init`. By the time the run comes back
`saved`, the `card_token.created` webhook has brought your server the token, so the app
only has to ask for the list again.

```dart
final run = await myApi.startCardSave();

final result = await GetPayInCheckout.saveCard(
  run.tokenizationUrl,
  OpenCheckoutOptions(
    returnUrl: 'myapp://payment-return',
    expectedInvoiceId: invoiceIdInCheckoutUrl(run.tokenizationUrl),
    title: 'Save your card',
  ),
);

switch (result.status) {
  case CardSaveStatus.saved:
    await myApi.refreshSavedCards();
  case CardSaveStatus.notSaved:
    showMessage(result.message ?? 'The card could not be saved.');
  case CardSaveStatus.cancelled:
    break;
}
```

`saveCard` is `open` with a different reader over the same run: the same validation, the
same one-at-a-time guard, the same in-app screen or browser sheet, the same strict reading
of the return link.

## The result

| `status`    | What it means                                                           | What to do                                     |
| ----------- | ----------------------------------------------------------------------- | ---------------------------------------------- |
| `saved`     | The card was vaulted.                                                   | Refresh your saved cards from your own server. |
| `notSaved`  | The card was refused, or the link could not be trusted to say it was.   | Show `message`. See `code` below.              |
| `cancelled` | The payer closed the screen.                                            | Nothing.                                       |

`verificationStatus` is what the link said about the verification invoice: `AUTHORIZED`
while the hold stands, `VOIDED` once it is released, `CAPTURED` if it was taken. None of
them is a failure, and none of them is ever `PAID`.

`code` is `null` for a card the gateway refused — the same way a declined payment carries
none. Only two values can appear:

| `code`                                    | What happened                                                      |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `CheckoutResultCode.unreadableReturnLink` | The link's own fields could not be read. Alert on it; it is a bug. |
| `CheckoutResultCode.wrongInvoice`         | The link named a different verification run.                       |

## The token is not here

The app-return bridge carries `success`, `invoice_id`, `invoice_status`, `message` and
`signature`, and nothing else. There is no card token on it, by design — a token that
unlocks a stored card has no business travelling through a public app scheme.

It reaches you on the **`card_token.created` webhook**, which is also what makes the save
real: a payer whose phone dies between the vaulting and the return link has still saved
their card. Treat the webhook as the record, exactly as you treat `invoice.paid` for a payment.

## Binding the run to its own result

`expectedInvoiceId` is the verification's invoice, and with it set, a return link naming
another run is refused. `/tokens/init` does not hand you that id directly — it is in the
`tokenization_url`, and `invoiceIdInCheckoutUrl` reads it out:

```dart
expectedInvoiceId: invoiceIdInCheckoutUrl(run.tokenizationUrl),
```

## Saving a card while taking a payment

A separate run is not always needed. `POST /v2/integration/init` with `tokenize: true`
vaults the card off a sale the payer is already making — one authorization, the sale stands,
the card is kept. That is an ordinary payment, so open it with `GetPayInCheckout.open` and
read it as one; the token still arrives by webhook.

## What cannot save a card

The payment sheet. PayLink refuses `tokenize` on a hosted-fields payment — the consent
wording would be on a form it does not own — and a card-save run reaches the sheet as
`fields_unsupported`, which sends the payer to the hosted checkout. There is no "save this
card" checkbox for that reason.

Hosted tokenization also needs CyberSource Unified Checkout on the account: it is the only
checkout that mints a token on the authorization. `/tokens/init` answers `403` otherwise.

## Next

[Taking payments](taking-payments.md) · [API reference](api.md) · [Security model](security.md)
