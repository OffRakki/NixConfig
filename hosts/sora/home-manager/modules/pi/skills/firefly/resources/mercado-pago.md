# Mercado Pago — API and statements

## API

Free REST API (no subscription) for fetching credit card transactions, account movements, and more.

### Setup

1. Go to https://developers.mercadopago.com.br/ -> Create an app
2. Generate an `access_token` (Bearer type) in the app dashboard
3. Store the token in sops as `mercadoPagoToken`

### Key endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /v1/payments/search` | Payments received/sent |
| `GET /v1/mercadopagoaccount/movements/search` | Account statement |

**Credit card:** use `/v1/payments/search` with `status=approved`.

**Account statement:** use `/v1/mercadopagoaccount/movements/search`.

### Auth

`Authorization: Bearer {access_token}` header.

```bash
curl -H "Authorization: Bearer $(cat /run/secrets/mercadoPagoToken)" \
  "https://api.mercadopago.com/v1/payments/search?limit=50"
```

### Relevant payment fields

| Field | Description |
|-------|-------------|
| `id` | MP payment ID |
| `status` | `approved`, `in_process`, `rejected` |
| `date_approved` | Settlement date |
| `transaction_amount` | Total BRL amount |
| `description` | Merchant description |
| `payment_method_id` | `account_money`, `pix`, `visa`, `master` |
| `operation_type` | `regular_payment`, `recurring_payment`, `money_exchange`, `partition_transfer`, `money_transfer` |
| `installments` | Number of installments |
| `card.last_four_digits` | Card suffix |

### Direction detection

Use `point_of_interaction.business_info.sub_unit`:
- `money_inflows` -> money received (deposit)
- `money_outflows` -> money sent (withdrawal)

### Pagination

Offset/limit based. Max 50 per page.

```
?limit=50&offset=0&sort=date_approved&criteria=desc
```

## Manual export (OFX/CSV)

Mercado Pago allows exporting statements through the app/site:

- **Digital account:** CSV or PDF via app -> Account -> Statement
- **Credit card:** Monthly invoice via app -> Card -> Invoices

### CSV format

Approximate CSV format:

```
Data,Descrição,Valor,Tipo
01/06/2026,Compra no Mercado Livre,R$ 150,00,saída
```

## See also

- `resources/auditing.md` — reconciliation patterns (apply to MP too)
- `resources/nubank-ofx.md` — many patterns apply (installments, IOF, date lag)
