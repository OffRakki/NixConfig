---
name: finances
description: Manage Lucky's personal finance Google Spreadsheet ("gastos"), Firefly III sync, 3-bucket monthly budget tracking, installment filtering, and tab layout conventions.
---

# Personal Finances (`gastos` Spreadsheet + Firefly III)

Use this skill alongside `firefly`, `gdrive`, and `gsheets` whenever working on Lucky's personal finance spreadsheet, syncing transactions/subscriptions between Firefly III and Google Sheets, or updating budget tracking and layout.

## Privacy & Discovery

- **Never hardcode** the spreadsheet ID, personal balances, real monetary caps, account numbers, or private bill details in NixConfig or skills.
- Resolve the spreadsheet ID dynamically at runtime via `gdrive`:

```bash
gdrive files search --query "name = 'gastos' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false"
```

- Read/write the sheet via `gsheets` (`gsheets readonly read`, `gsheets mutate batch`, `gsheets mutate raw-batch`).
- Keep Firefly III and the spreadsheet in sync whenever adding, editing, or deleting transactions or recurring subscriptions (load `firefly` for Firefly III API details).

## Spreadsheet Architecture

Design rules: **visual, clean, scannable, no charts** (prefer KPI cards, color-coded status pills, conditional formatting, and `REPT` progress bars). Keep `Inter` font, `R$` currency format (`"R$" #,##0.00`), and hidden gridlines on dashboard tabs.

### `Resumo` (Dashboard)

- **Hero & Selector (`Rows 1–6`)**:
  - `B2`: editable `Mês em foco` (`YYYY-MM` text) — drives all monthly metrics across the dashboard.
  - 4 KPI cards: `Patrimônio Líquido`, `Gasto no Mês`, `Restante da Meta`, `Assinaturas / Mês`.
- **`PATRIMÔNIO & CONTAS` (`A8:E18`) & `FATURAS EM ABERTO` / `MÊS EM FOCO` (`G8:K11`)**:
  - Editable real-world account/investment balances (`B9:B15`) and open credit card bills (`H9:H10`) highlighted in soft blue.
  - Auto-computed Gross Assets (`B16`), Open Bills (`B17`), Net Worth (`B18`), and monthly cashflow (`K9:K11`).
- **`LIQUIDEZ & COMPROMISSOS` (`G13:K20`)**:
  - Liquidity breakdown (`Contas + Cofrinhos`, `Saldo Livre pós-Faturas`, `Total Investido`)
  - Monthly 3-bucket breakdown (`Parcelado no Mês`, `Gastos Fixos (Assinaturas)`, `Gastos a Mais (Avulsos)`)
  - `Parcelas Futuras` (scheduled future installments)
- **`METAS DO MÊS (3 BALDES)` (`A22:E26`) & `COMPOSIÇÃO & PROGRESSO DA META` (`G22:K26`)**:
  - Dedicated 3-bucket target card with editable blue monthly caps (`B23:B25`) for Fixed, Installments, and Extra/Leisure spending, live `Gasto`, `Restante`, `Dentro da meta` / `Acima da meta` pills, and `REPT("█", ...)` progress bars.
- **`GASTOS POR CATEGORIA` (`A28:E40`) & `PANORAMA MENSAL` (`G28:K40`)**:
  - Category totals for the focused month vs overall, and multi-month timeline against the monthly cap.

### `Lançamentos` (Master Ledger)

- **Frozen Rows 1–4** (kept above the Basic Filter so filtering never hides controls):
  - **Row 1**: `Ano` dropdown (`C1`), `Limpar filtro` checkbox (`E1`), live visible sum `=SUBTOTAL(109,E5:E)` (`G1`), and visible item count `=SUBTOTAL(103,A5:A)` (`H1`).
  - **Rows 2–3**: 12 clickable month checkboxes (`A3:L3`, labels `'01 Jan`..`'12 Dez` in `A2:L2`) backed by a bound `onEdit(e)` Apps Script that mutates the main table's Basic Filter on `Parcelado` (col 7) and `Mês` (col 11).
  - **Row 4**: Table headers (`Data`, `Descrição`, `Categoria`, `Tipo`, `Valor`, `Status`, `Parcelado`, `Destino`, `Assinatura`, `Observações`, `Mês`, `Valor Líquido`, `Orçamento`, `ID`) with Basic Filter starting at `A4:N503`.
- **Header-row `ARRAYFORMULA`s**:
  - `F4` (`Status`): `Realizado` vs `Futuro` based on `TODAY()`.
  - `K4` (`Mês`): `TEXT(A5:A,"yyyy-mm")`.
  - `L4` (`Valor Líquido`): signed amount (`-E` for `Saída`, `+E` for `Entrada`).
- **Dropdowns**: `Categoria`, `Tipo`, `Parcelado` (`Sim`/`Não`), `Orçamento`.

### `Assinaturas` (Subscriptions)

- Frozen Row 1 summary bar (`SUMIF` active monthly total, `*12` annual total, `COUNTIF` active count).
- Row 3 headers; Rows 4+ recurring subscriptions.

### `Orçamento` (Budget)

- Monthly cap and category overview referenced by `Resumo`.

### `VR` Tab — Strict Read-Only Values Rule

- **Never modify values, formulas, or table data on the `VR` tab** unless Lucky explicitly asks to change its data.
- Visual/formatting-only updates are allowed when requested.

## 3-Bucket Spending Classification

All monthly summaries on `Resumo` split `Tipo = "Saída"` transactions in `Lançamentos` into three mutually exclusive buckets that sum exactly to `Gasto no Mês`:

1. **Parcelados**: `Parcelado = "Sim"` (installments, typically `N/M` descriptions or explicitly flagged).
2. **Gastos Fixos (Assinaturas)**: `Parcelado <> "Sim"` AND `Assinatura <> ""`.
3. **Gastos a Mais (Avulsos / Lazer e Extras)**: `Parcelado <> "Sim"` AND `Assinatura = ""`.

## Sync & Reconciliation Rules

- **Dual-write**: When logging new expenses or deleting mistakes, update both Firefly III and `Lançamentos` (and `Assinaturas` + Firefly recurrence/bill for subscriptions).
- **Firefly recurrences**: `POST /api/v1/recurrences` requires `destination_id` (not just `destination_name`) and `transactions[0].bill_id` to link to a bill.
- **Month spending vs open card bills**: Expect a gap between `Gasto no Mês` and open credit card statements due to billing-cycle overlap (prior-month charges on the current statement) and payment-method mix (PIX/debit vs credit card).

## Google Sheets API & CLI Gotchas

- **`en_US` locale date auto-parsing**: Always prefix `YYYY-MM` and short month labels (`'01 Jan`, `'03 Mar`, `'06 Jun`, `'07 Jul`, `'11 Nov`, `'2026-11`) with `'` and format cells as `TEXT`, or `USER_ENTERED` parses them as dates and breaks `SUMIFS` against `TEXT(A5:A,"yyyy-mm")`.
- **Conditional formatting API**: Use `NUMBER_GREATER_THAN_EQ` (not `NUMBER_GREATER_OR_EQUAL`). Delete stale rules before re-applying to avoid stacking duplicates.
- **Native typed Tables**: Typed Tables block `setDataValidation`; removing a table with `deleteTable` wipes its cells, so rewrite data immediately afterward.
- **Filtered rows**: Never `mergeCells` across rows inside an active `BasicFilter`. Keep interactive controls in frozen rows above the filter range.
- **`gsheets` CLI `insertDimension`**: `startIndex: 0` can be dropped by Go `omitempty`; to insert above row 1, insert at `startIndex: 1` and `copyPaste` row 1 down.
- **Image export**: `gsheets readonly export --format png` requires `pdftoppm` (`nixpkgs#poppler-utils`) in `PATH`.
