---
name: firefly
description: Manage your finances in Firefly III (transactions, budgets, subscriptions, reimbursement tracking)
---

# Firefly III

This skill has supporting resources — load them as needed:

- `resources/private.md` — accounts, budgets, categories, income, quirks, subscriptions, instance config
- `resources/auditing.md` — full audit workflow and reconciliation patterns
- `resources/mercado-pago.md` — Mercado Pago API + statement format
- `resources/btg.md` — BTG Pactual statement format (manual export)
- `resources/nubank-ofx.md` — OFX/PDF statement format and memo mappings
- `scripts/firefly_client.py` — Firefly III API client (urllib-only, zero deps)
- `scripts/mercado_pago.py` — fetch Mercado Pago transactions via API
- `scripts/expenses.py` — monthly budget overview with hierarchical tables

## Quick overview

Wrappers are available in PATH with the PAT path pre-injected from sops:

- `firefly-expenses` — monthly budget overview
- `firefly-api` — interactive API client exploration

When asked for a financial overview over a date range (e.g. "how much did I spend Jan-Mar?" or "show me my finances for the last 3 months"), use:

```
firefly-expenses [start_month] [end_month]
```

It pulls budgets and transactions from the API (handling split transactions correctly), then prints a hierarchical budget/category table with monthly columns. Below the categories it shows TOTAL EXPENSES, REVENUE, NET, BUDGETED (sum of all budget caps), and LEFT (budgeted minus expenses) — all color-coded.

**Invocation shortcuts:**

```
firefly-expenses                     # current month only — quick budget pulse check
firefly-expenses 2026-05             # May through current month — side-by-side last month vs now
firefly-expenses 2025-12 2026-06     # custom range with Total/Avg columns
```

**Table columns:** Monthly columns (spent/limit for budget rows), then Total and Avg/mo when there are 2+ *completed* months in the range. A vertical ruler (`|`) separates monthly data from the Total/Avg columns. The current (partial) month — the last column when it includes the current month — is marked with `*` in the header and rendered in italic throughout.

**Avg/mo & Total:** both exclude the last month when it's the current (partial) month, to avoid skew. Only shown when there are 2+ completed months in the range.

**Zero-spending budgets:** budgets that have a limit set but zero spending in the range still appear in the table with `0/limit`, so you can see the full budget picture.

## Auth

Uses JWT Personal Access Token (Passport). Generate one at `http://localhost/profile` -> OAuth -> Create new token. The PAT is stored as a sops secret (`fireflyPat`) and injected into wrapper scripts automatically. The raw scripts fall back to `/run/secrets/fireflyPat` when the env var is unset.

### Environment variables

All scripts respect these env vars to override compiled-in defaults:

| Env var | Controls | Default |
|---|---|---|
| `FIREFLY_BASE` | Firefly III instance URL | `http://localhost` |
| `FIREFLY_TOKEN_PATH` | Path to PAT file | `/run/secrets/fireflyPat` (managed by sops) |
| `MP_ACCESS_TOKEN_PATH` | Path to Mercado Pago access token | `/run/secrets/mercadoPagoToken` (managed by sops) |

## Python API client

A reusable module lives at `scripts/firefly_client.py` — zero external deps (uses `urllib.request`).

```python
from firefly_client import FireflyClient

ff = FireflyClient()

# -- Summary (GET /api/v1/summary/basic) -------------------------------------
s = ff.summary(start="2026-01-01", end="2026-06-30")
for key, entry in s.items():
    print(entry["title"], entry["monetary_value"])

# -- Transactions (GET /api/v1/transactions) ---------------------------------
# Returns groups ; each group has a transactions[] array.
groups = ff.transactions(limit=50, page=1, account_id=ACCOUNT_ID,
                         start="2026-06-01", end="2026-06-30")
for group in groups.get("data", []):
    gid = group["id"]
    for split in group["attributes"]["transactions"]:
        print(gid, split["date"][:10], split["amount"], split["description"])

# -- Get a single group (GET /api/v1/transactions/{id}) -----------------------
group = ff.transaction(GROUP_ID)
splits = group["data"]["attributes"]["transactions"]
print(f"Group {GROUP_ID} has {len(splits)} split(s)")

# -- Search (GET /api/v1/search/transactions) ---------------------------------
r = ff.search("query", limit=20)

# -- Categories / Budgets / Subscriptions (GET) -------------------------------
for c in ff.categories():    print(c["id"], c["attributes"]["name"])
for b in ff.budgets():       print(f"[{b['id']}] {b['attributes']['name']}")
for sub in ff.subscriptions(): print(sub["attributes"]["name"],
                                      sub["attributes"]["amount_avg"])

# -- Create (POST /api/v1/transactions) ---------------------------------------
# 1 split = single, 2+ = split. group_title required when len(splits) > 1.
resp = ff.create_transaction([{
    "type": "withdrawal",
    "date": "2026-06-12",
    "amount": "42.50",
    "description": "Something",
    "source_id": SOURCE_ACCOUNT_ID,
    "destination_name": "Some expense",
    "category_name": "Some category",
}])
gid = resp["data"]["id"]

# -- Edit (GET group, modify array, PUT /api/v1/transactions/{id}) ------------
group = ff.transaction(gid)
splits = group["data"]["attributes"]["transactions"]
for split in splits:
    if split["transaction_journal_id"] == TARGET_JID:
        split["description"] = "New title"
        split["category_name"] = "Some category"
        break
else:
    raise ValueError(f"Split {TARGET_JID} not found in group {gid}")
ff.update_transaction(gid, splits, group_title="Group title")

# -- Delete (DELETE /api/v1/transactions/{id}) ---------------------------------
ff.delete_transaction(gid)
```

## Mercado Pago API (free, no subscription)

See `resources/mercado-pago.md` for endpoints, auth, and data shapes.

```bash
python3 /path/to/mercado_pago.py payments       # credit card transactions
python3 /path/to/mercado_pago.py movements       # account movements
python3 /path/to/mercado_pago.py payments 2026-01-01 2026-06-30  # date range
```

The access token is stored as a sops secret (`mercadoPagoToken`). A wrapper
(`firefly-mp`) can be added to inject it automatically.

## Recurring Transactions vs Bills

Firefly III has two separate features for recurring items:

- **Bills** (API: `/bills` or `/subscriptions`) — passive trackers. They store expected amounts, dates, and paid history but do NOT auto-create transactions. Use these to track recurring obligations.
- **Recurring Transactions** (API: `/recurrences`) — auto-create transaction groups on a schedule (daily, weekly, monthly). These are the actual automation engine.

A recurring transaction can link to a bill via `transactions[0].bill_id`. When set, the cron reads `RecurrenceTransactionMeta` on auto-creation to set `bill_id` on the generated transaction splits.

### Working with recurring transactions via API

**Create a monthly recurring transaction:**

```json
POST /api/v1/recurrences
{
  "type": "withdrawal",
  "title": "Meli+",
  "first_date": "2026-07-01",
  "repeat_freq": "monthly",
  "repeat_until": "2030-12-31",
  "repetitions": [{"type": "monthly", "moment": "1"}],
  "transactions": [{
    "source_id": "1", "destination_id": "10",
    "amount": "9.90", "description": "Meli+ Level 6",
    "category_id": "10", "budget_id": "1", "currency_id": "13",
    "bill_id": "1"
  }],
  "active": true, "apply_rules": true
}
```

**Key gotchas:**

- `nr_of_repetitions: 0` is invalid (must be >=1). Use `repeat_until` instead for unlimited runs.
- `repetitions` array defines when in the period: `[{"type": "monthly", "moment": "1"}]` = 1st of month.
- **`bill_id` goes on the transaction level** (`transactions[0].bill_id`), NOT the recurrence level. Despite GET responses showing `subscription_id`, the write field is `bill_id`.
- `nr_of_repetitions` and `repeat_until` are mutually exclusive.

**Link an existing recurrence to a bill:**

```python
# PUT /api/v1/recurrences/{id} — include the transaction's `id` field + `bill_id`
payload = {
    "title": recurrence.title,
    "repeat_until": "2030-12-31",
    "repetitions": [...],
    "transactions": [{"id": tx_id, "bill_id": BILL_ID, ...}]
}
```

The `GetRecurrenceData` trait extracts `bill_id` from `transactions[0].bill_id`. `RecurrenceUpdateService::updateCombination()` calls `setBill()` which stores it in `RecurrenceTransactionMeta` (`rt_meta`, `name='bill_id'`).

**Linking a transaction to a bill:**

```python
split["bill_id"] = "1"
ff.update_transaction(group_id, [split], group_title="Meli+")
```

This auto-populates `subscription_id` and `subscription_name`.

### Cron timer

The system timer `firefly-iii-cron.timer` fires daily at midnight (randomized ±30min). It runs `php artisan firefly-iii:cron`, processing recurrences, bills, budgets, and categories. `Persistent=true` catches up missed runs on next boot.

```bash
systemctl list-timers | grep firefly
```

## Tips

- `source_id` is the account money comes FROM
- `destination_name` creates an expense account on the fly if it doesn't exist
- Firefly deduplicates on `import_hash_v2` — same amount+description+date+account won't create duplicates
- The API returns paginated results; check `meta.pagination.total_pages`
- Default `limit` is 50; set higher when available to reduce round trips
- Tags are returned as arrays of strings under each transaction
- **Everything is a transaction group.** Every API response and write operation works with groups. A "single" transaction is just a group whose `transactions[]` array has one entry. Always work with the full group — to edit, GET the group by its ID, modify the `transactions[]` array, then PUT it back. **You must send EVERY split in the group** — sending only the split you changed removes all the others.
- **Creating a split:** Pass multiple entries in the `transactions[]` array. A `group_title` is required when there are multiple splits. Each split is a full transaction object with its own `type`, `amount`, `description`, `source_id`, `destination_name`, `category_name`, and a `transaction_journal_id` assigned on creation.
- **Group ID and journal ID — two levels of identity:**

  - **Group `id`** identifies the whole transaction group. Use this for API calls and web UI URLs. Every response from `GET /transactions` returns groups, each with an `id` at the top level.
  - **`transaction_journal_id`** identifies a single entry *within* a group. Use this when you need to edit one split inside a multi-split group — search for it in the `transactions[]` array and modify that entry, keeping all other splits unchanged.
  - **When you GET a group**, you get both: the group `id` at the response root, and each split's `transaction_journal_id` inside `transactions[]`.
  - **Split array order is NOT stable.** Never index by position — always match by `transaction_journal_id`.
- **Editing:** Send only the fields you want to change — everything else stays as-is. Both `category_name` and `category_id` work; same for `budget_name` / `budget_id`. To clear a nullable field: both JSON `null` and empty string `""` work.
- **`destination_id` overrides `destination_name`:** When changing the destination of a transaction, setting `destination_name` alone may silently fail if the split still has a stale `destination_id` pointing to the old account. Always set `destination_id` to `null` alongside the new `destination_name` to ensure the change sticks.
- **Reconciled transactions block API edits:** The API returns HTTP 422 for PUT on reconciled transactions. Unreconcile first via the web UI (`/transactions/edit/<group_id>` -> uncheck "Reconciled"), then edit.
- **Multi-split PUT requires all splits + group_title:** When updating a multi-split group via PUT, send EVERY split in the `transactions[]` array and include `group_title`. Sending only the split you want to change silently removes the others.
- **Self-transfer detection in MP imports:** The `import_mp.py` script detects self-transfers by matching the counterparty CPF (426.334.128-74) from `payer.identification.number` or `collector.identification.number`. Add known PIX keys to `SELF_PIX_KEYS` for additional matching. Transfers to the same CPF are skipped as internal movements.
- **Fuel quantity enrichment:** When liters are missing from fuel transaction description, first check bank/MP data, receipt, or existing notes for exact quantity. If absent, ask Lucky for exact liters or effective per-liter price after discounts/promotions. If Lucky can't provide them, research plausible local price for place/date, mark result as estimate, compute `liters = total_amount / effective_price_per_liter`, then append quantity to description in existing style, e.g. `Combustível, 47,6 L` or `Etanol Comum, 51,26 L`.

## Web UI URLs

When user asks to edit something manually, they want a web UI URL to it.

All three URLs use the **group `id`**, **not** `transaction_journal_id` and **not** `transaction_id`:

- **Single edit:** Edit a single transaction:
  `http://localhost/transactions/edit/<group_id>`
- **Bulk edit:** Change a single field (e.g. budget) across many transactions at once:
  `http://localhost/transactions/bulk/edit/<group_id>,<group_id>,...`
- **Mass edit:** Edit all fields individually for each transaction in a list:
  `http://localhost/transactions/mass/edit/<group_id>,<group_id>,...`

## Budget limits vs auto-budgets

Firefly III has two separate concepts that look similar:

- **`auto_budget_amount`** on `/budgets` — set for auto-recurring budgets. Returns `null` for budgets with manually-set amounts.
- **Budget limits** via `/budget-limits` or `/budgets/{id}/limits` — these are the manually-set monthly caps. When present for a given month, they **override** `auto_budget_amount`.

**Fallback rule:** when no budget limit exists for a given month, the `auto_budget_amount` is the cap. This is the expected, normal behavior — not a gap. A newly-created budget won't have historical limits; the auto_budget applies retroactively. Always check both sources and use budget limits when available, falling back to auto_budget_amount when they're absent.

**Budget limits** are fetchable live via the `budget-limits` endpoint. `expenses.py` displays caps alongside spending in budget rows (manual limits first, auto_budget fallback) and aggregates them in the BUDGETED/LEFT summary rows.

**Auto-budget rollover:** Some budgets use Firefly's next-month rollover — overspending in one month reduces the next month's cap; underspending increases it. This is intentional for budgets where purchases don't fit neat monthly boundaries (every 2, 3, or 6 weeks) but average out over time. Don't interpret a single-month overage as structural overspend — look at the multi-month average instead.

**Budget nature:**

- Some budgets are **variable** — spending fluctuates significantly. Caps are targets, not fixed costs.
- Some budgets are **fixed-ish** — nearly 100% recurring bills. When these show under cap mid-month, it means bills haven't hit yet, not that spending is under control.

See `resources/private.md` for the full budget list with IDs, caps, rollover budgets, and nature.

## Bills (passive subscription trackers)

**Reading bill data from the API:**

- Amount is in `amount_min`, `amount_max`, `amount_avg` (all strings). Use `amount_avg`.
- **USD-denominated subs:** `amount_avg` stores the *foreign currency* value. Actual BRL cost = foreign amount x rate x 1.064 (IOF+spread) — varies with exchange rate. Don't trust API amounts for USD items; check actual BRL transactions instead.
- The `skip` field means "skip N occurrences." A `weekly, skip:3` bill fires once every 4 weeks. Without understanding `skip`, the monthly cost estimate will be wildly wrong (e.g., R$ 440/week looks like R$ 1,760/mo when it's actually R$ 476.67/mo).

**Effective monthly cost formula:**

```
if freq == 'weekly':     effective = amount * (52/12) / (skip + 1)
if freq == 'monthly':    effective = amount / (skip + 1)
if freq == 'yearly':     effective = amount / (12 * (skip + 1))
if freq == 'half-year':  effective = amount / (6 * (skip + 1))
```

See `resources/private.md` for the actual subscription list with names, amounts, and skip values.

## Category audit workflow

See `resources/auditing.md` for the full workflow: fetching transactions,
auditing against the category/budget mapping, fixing issues with `ask_user` or
`ask_user_question` prompts, handling ambiguous rides, and cross-referencing against bank data
(Mercado Pago API, or manual statement reviews).

## OFX statement audit

See `resources/auditing.md` for reconciliation patterns (IOF, installments,
date lag, merchant name matching, shared expenses, and more).

## Getting started

1. Register an account at `http://localhost`
2. Generate a PAT at `http://localhost/profile` -> OAuth -> Create new token
3. The PAT is already stored as a sops secret (`fireflyPat`) — it's injected into `firefly-expenses` and `firefly-api` wrapper scripts automatically
4. Populate `resources/private.md` with accounts, budgets, categories
5. Configure Mercado Pago API token (`mercadoPagoToken` in sops) for automatic transaction fetching
