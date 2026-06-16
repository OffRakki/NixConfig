#!/usr/bin/env python3
"""Fetch Mercado Pago payments and import into Firefly III.

Usage:
  python3 import_mp.py                           # last 30 days
  python3 import_mp.py --start 2026-01-01 --end 2026-06-16
  python3 import_mp.py --dry-run                  # preview without importing
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ── Configuration ──────────────────────────────────────────────────────────

DEKKI_ACCOUNT_ID = "1"
PAIS_ACCOUNT_ID = "6"
TOTAL_BUDGET_ID = "1"
CARRO_CATEGORY = "Carro"

CAR_KEYWORDS = ["etanol", "gasolina", "posto", "pedagio", "mecanico",
                "oficina", "revisao", "oleo", "troca oleo", "pneu",
                "borracharia", "estacionamento", "florio", "auto posto",
                "combustivel", "lubrificante", "alinhamento", "balanceamento"]

# Known CPFs for self-transfer detection
# PIX/bank transfers to/from these CPFs are internal movements, not real expenses
SELF_CPFS = {"42633412874"}
SELF_PIX_KEYS: set[str] = set()  # Add known PIX keys here as they emerge

TOKEN_PATH = os.environ.get("FIREFLY_TOKEN_PATH", "/run/secrets/fireflyPat")
FF_BASE = os.environ.get("FIREFLY_BASE", "http://localhost")

MP_TOKEN_PATH = os.environ.get("MP_ACCESS_TOKEN_PATH",
                                "/run/secrets/mercadoPagoToken")
MP_API = "https://api.mercadopago.com"

# ── Expense / Revenue accounts to create in Firefly ───────────────────────

REVENUE_ACCOUNTS = {
    "Recebimentos": {},
}

EXPENSE_ACCOUNTS = {
    "Assinaturas": {},
    "Compras": {},
    "PIX enviado": {},
    "Diversos": {},
}

# ── Categorization rules ───────────────────────────────────────────────────
# Matched by description substring (case-insensitive)

CATEGORY_RULES = [
    # (substring, is_expense, dest_account_name)
    ("assinatura do meli+", True, "Assinaturas"),
    # statement_descriptor matches
    ("mp*melimais", True, "Assinaturas"),
]


def is_car_expense(description):
    text = description.lower()
    return any(kw in text for kw in CAR_KEYWORDS)


def is_self_transfer(payment):
    """Check if a payment is a transfer between Lucky's own accounts."""
    # PIX keys
    alias = ""
    poi = payment.get("point_of_interaction", {}).get("transaction_data", {})
    bank_info = poi.get("bank_info", {})
    collector = (bank_info or {}).get("collector", {})
    if collector:
        alias = (collector or {}).get("account_alias") or ""
    if alias in SELF_PIX_KEYS:
        return True

    # CPF from payer (incoming PIX: someone paid Lucky)
    payer = payment.get("payer", {})
    payer_id = (payer or {}).get("identification", {})
    payer_cpf = (payer_id or {}).get("number", "")
    if payer_cpf in SELF_CPFS:
        return True

    # CPF from collector (outgoing PIX: Lucky paid someone)
    coll_id = payment.get("collector", {}).get("identification", {})
    coll_cpf = (coll_id or {}).get("number", "")
    if coll_cpf in SELF_CPFS:
        return True

    return False


def ff_get_token():
    with open(TOKEN_PATH) as f:
        return f.read().strip()


def ff_headers():
    return {
        "Authorization": f"Bearer {ff_get_token()}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def ff_api(method, path, body=None):
    url = f"{FF_BASE}/api/v1/{path.lstrip('/')}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=ff_headers())
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        # 409 = duplicate
        if e.code == 409:
            return None
        raise SystemExit(f"FF HTTP {e.code}: {body}")


def mp_get(path, params=None):
    token = open(MP_TOKEN_PATH).read().strip()
    url = f"{MP_API}{path}"
    if params:
        url += "?" + "&".join(f"{k}={urllib.parse.quote(str(v))}"
                              for k, v in params.items())
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


def mp_fetch_payments(date_from, date_to):
    """Fetch all payments from MP with full pagination."""
    params = {
        "limit": 50,
        "offset": 0,
        "sort": "date_approved",
        "criteria": "asc",
        "begin_date": f"{date_from}T00:00:00.000-03:00",
        "end_date": f"{date_to}T23:59:59.999-03:00",
    }
    all_payments = []
    while True:
        data = mp_get("/v1/payments/search", params)
        results = data.get("results", [])
        all_payments.extend(results)
        total = data.get("paging", {}).get("total", len(results))
        params["offset"] += 50
        if params["offset"] >= total:
            break
    return all_payments


def categorize(payment):
    """Return (is_expense: bool, account_name: str)."""
    desc = (payment.get("description") or "").lower()
    statement_desc = (payment.get("statement_descriptor") or "").lower()
    text = f"{desc} {statement_desc}"

    for substr, is_exp, acct in CATEGORY_RULES:
        if substr in text:
            return is_exp, acct

    method = payment.get("payment_method_id", "")
    op_type = payment.get("operation_type", "")
    sub_unit = (payment.get("point_of_interaction", {})
                .get("business_info", {}).get("sub_unit", ""))
    sub_type = (payment.get("point_of_interaction", {})
                .get("sub_type", ""))

    # Determine direction
    is_inflow = "inflow" in sub_unit

    if method == "visa" or method == "master":
        return True, "Compras"

    if method == "pix":
        if is_inflow:
            return False, "Recebimentos"
        else:
            return True, "PIX enviado"

    if method == "account_money":
        if op_type == "money_exchange":
            return not is_inflow, "Investimentos"
        if op_type == "partition_transfer":
            return not is_inflow, "Investimentos"
        if is_inflow:
            return False, "Recebimentos"
        return True, "Diversos"

    # Fallback
    if is_inflow:
        return False, "Recebimentos"
    return True, "Diversos"


def get_description(payment):
    desc = payment.get("description")
    if desc:
        return desc
    sd = payment.get("statement_descriptor")
    if sd:
        return sd.strip()
    method = payment.get("payment_method_id", "")
    sub_type = (payment.get("point_of_interaction", {})
                .get("sub_type", ""))
    collector = (payment.get("point_of_interaction", {})
                 .get("transaction_data", {})
                 .get("bank_info", {})
                 .get("collector", {}))
    alias = (collector or {}).get("account_alias")
    payer = (payment.get("point_of_interaction", {})
             .get("transaction_data", {})
             .get("bank_info", {})
             .get("payer", {}))
    payer_name = (payer or {}).get("long_name", "")

    if alias:
        return f"PIX para {alias}"
    if payer_name:
        return f"PIX de {payer_name}"
    return f"{method.upper()} - sem descricao"


def ensure_account(name, atype):
    """Create account in Firefly if it doesn't exist. Return account ID."""
    # Check if exists
    data = ff_api("GET", f"accounts?type={atype}&limit=100")
    for acct in data.get("data", []):
        if acct["attributes"]["name"].lower() == name.lower():
            return acct["id"]
    # Create - Firefly III expects data at root level
    body: dict = {"name": name, "type": atype}
    if atype == "asset":
        body["account_role"] = "defaultAsset"
    resp = ff_api("POST", "accounts", body)
    if resp:
        new_id = resp["data"]["id"]
        print(f"  Created {atype} account: {name} (id={new_id})")
        return new_id
    return None


def build_transaction(payment, dry_run):
    """Build a Firefly transaction dict from a MP payment.
    
    Returns (group_title, splits) or None if deduplicated.
    """
    date = (payment.get("date_approved") or
            payment.get("date_created", ""))[:10]
    if not date:
        return None

    amount = f"{payment['transaction_amount']:.2f}"
    mp_id = str(payment["id"])
    description = get_description(payment)
    is_expense, acct_name = categorize(payment)

    # Dedup: check if MP ID already exists in FF notes
    existing = ff_api("GET",
        f"transactions?limit=50&start={date}&end={date}")
    if existing:
        for group in existing.get("data", []):
            for split in group["attributes"]["transactions"]:
                notes = split.get("notes") or ""
                if f"mp_id={mp_id}" in notes:
                    return None  # Skip - already imported

    budget_id = TOTAL_BUDGET_ID

    if is_expense:
        source_id = PAIS_ACCOUNT_ID if is_car_expense(description) else DEKKI_ACCOUNT_ID
        split = {
            "type": "withdrawal",
            "date": date,
            "amount": amount,
            "description": description,
            "source_id": source_id,
            "destination_name": acct_name,
            "notes": f"Importado do MP. mp_id={mp_id}",
            "budget_id": budget_id,
        }
        if is_car_expense(description):
            split["category_name"] = CARRO_CATEGORY
    else:
        split = {
            "type": "deposit",
            "date": date,
            "amount": amount,
            "description": description,
            "source_name": acct_name,
            "destination_id": DEKKI_ACCOUNT_ID,
            "notes": f"Importado do MP. mp_id={mp_id}",
        }

    return (description, [split])


def import_payments(payments, dry_run):
    """Import list of MP payments into Firefly."""
    total = len(payments)
    skipped = 0
    imported = 0
    errors = 0

    for i, p in enumerate(payments):
        if p.get("status") != "approved":
            skipped += 1
            continue

        op_type = p.get("operation_type", "")
        if op_type == "partition_transfer":
            # Internal transfer between Lucky's own accounts (MP -> BTG, etc.)
            skipped += 1
            continue
        if op_type == "recurring_payment":
            # Handled by Firefly subscriptions — skip to avoid duplicates
            skipped += 1
            continue

        desc_check = (p.get("description") or "").lower()
        if "cashback" in desc_check or "earn_buy" in desc_check:
            # Cashback and MUSDBRL investment earnings — not real revenue
            skipped += 1
            continue

        if is_self_transfer(p):
            # PIX/bank transfer to/from own accounts — not real expense/income
            skipped += 1
            continue

        result = build_transaction(p, dry_run)
        if result is None:
            skipped += 1
            continue

        title, splits = result

        if dry_run:
            date = (p.get("date_approved") or p.get("date_created", ""))[:10]
            amt = p["transaction_amount"]
            dest = splits[0].get("destination_name") or splits[0].get("source_name", "?")
            src = splits[0].get("source_name") or splits[0].get("source_id", "?")
            pp = splits[0].get("type", "?")
            cat = splits[0].get("category_name", "")
            tag = f" cat={cat}" if cat else ""
            print(f"  [{date}] {amt:>10.2f} {pp:12} {src:12} -> {dest:20} | {title[:40]}{tag}")
            imported += 1
            continue

        try:
            resp = ff_api("POST", "transactions",
                          {"transactions": splits})
            if resp is None:
                # 409 duplicate
                skipped += 1
            else:
                gid = resp["data"]["id"]
                print(f"    -> Created group {gid}: {title[:50]}")
                imported += 1
        except SystemExit as e:
            print(f"    -> ERROR: {e}", file=sys.stderr)
            errors += 1

        # Rate limit: be gentle
        if i % 20 == 19:
            time.sleep(1)

    return imported, skipped, errors


def main():
    parser = argparse.ArgumentParser(
        description="Import Mercado Pago payments into Firefly III")
    parser.add_argument("--start", default="",
                        help="Start date (YYYY-MM-DD). Default: 30 days ago")
    parser.add_argument("--end", default="",
                        help="End date (YYYY-MM-DD). Default: today")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview only, no import")
    args = parser.parse_args()

    # Default: last 30 days
    from datetime import datetime, timedelta
    end = args.end or datetime.now().strftime("%Y-%m-%d")
    if args.start:
        start = args.start
    else:
        start = (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d")

    print(f"Fetching MP payments from {start} to {end}...")
    payments = mp_fetch_payments(start, end)
    print(f"  Found {len(payments)} payments total\n")

    # Ensure accounts exist (only if not dry-run)
    if not args.dry_run:
        print("Ensuring accounts and categories exist in Firefly...")
        for name in REVENUE_ACCOUNTS:
            ensure_account(name, "revenue")
        for name in EXPENSE_ACCOUNTS:
            ensure_account(name, "expense")
        # Ensure Carro category exists
        cats = ff_api("GET", "categories")
        if cats:
            found = any(c["attributes"]["name"] == CARRO_CATEGORY
                        for c in cats.get("data", []))
            if not found:
                ff_api("POST", "categories", {"name": CARRO_CATEGORY})
                print(f"  Created category: {CARRO_CATEGORY}")
        print()

    print(f"Processing payments...")
    imp, skip, err = import_payments(payments, args.dry_run)
    
    print(f"\n{'='*50}")
    print(f"  Total:    {len(payments)}")
    print(f"  Skipped:  {skip}")
    print(f"  Imported: {imp}")
    print(f"  Errors:   {err}")
    print(f"{'='*50}")

    if args.dry_run:
        print("\nRun without --dry-run to actually import.")


if __name__ == "__main__":
    main()
