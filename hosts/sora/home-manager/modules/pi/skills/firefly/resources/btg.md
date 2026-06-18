# BTG Pactual — Statements and formats

## Manual export

BTG **has no free public API**. Access is via manual export:

### Checking account statement

Via app/site:
1. Checking Account -> Statements -> Select period
2. Format: **PDF** (analytical statement)
3. No native OFX export

### Credit card statement

Via app/site:
1. Cards -> Current/previous invoices -> Download
2. Format: **PDF** with purchase details
3. Each purchase shows: date, merchant, amount, installment count

### PDF conversion

To reconcile BTG PDF statements in Firefly:

1. Extract text: `pdftotext` or `python3 -m pymupdf`
2. Parse transaction lines (date | description | value)
3. Feed into Firefly via API

A parse script could be created if needed, but first check if BTG offers CSV via less obvious endpoints.

## BTG-specific notes

- **Installments:** BTG typically shows installments as separate lines in the invoice, like Nubank/Mercado Pago.
- **IOF:** BTG cards follow standard market patterns (IOF on international purchases, reversed days later).
- **Investments:** Stocks, Treasury Direct, CDBs live in the investments section — **not** in the checking account statement. These movements need manual Firefly entries as transfers to investment accounts.

## Alternatives

- **OFX/CSV via bank chat:** Some banks offer CSV export by request via chat/email — try BTG support.

## See also

- `resources/auditing.md` — reconciliation patterns
- `resources/nubank-ofx.md` — OFX patterns that partially apply
