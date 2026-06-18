#!/usr/bin/env python3
"""Fetch Mercado Pago transactions and print summary.

Uses the Mercado Pago API (free) to pull payments and account movements.

Prerequisites:
  1. Create an app at https://developers.mercadopago.com.br/
  2. Set MP_ACCESS_TOKEN_PATH to a file containing your access_token,
     or run from the wrapper (which injects it from sops).

Usage:
  python3 mercado_pago.py payments                  # credit card payments
  python3 mercado_pago.py movements                 # account movements
  python3 mercado_pago.py payments 2026-01-01 2026-06-30  # date range
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.mercadopago.com"
_token_path = os.environ.get("MP_ACCESS_TOKEN_PATH",
                              "/run/secrets/mercadoPagoToken")
ACCESS_TOKEN = open(_token_path).read().strip()


def _get(path, params=None):
    url = f"{API_BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {ACCESS_TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise SystemExit(f"HTTP {e.code}: {body}")


def fetch_all(path, params=None):
    """Paginate Mercado Pago's offset/limit API."""
    params = dict(params or {})
    params.setdefault("limit", 50)
    params.setdefault("offset", 0)
    results = []
    while True:
        data = _get(path, params)
        items = data.get("results") or data.get("data") or []
        results.extend(items)
        total = data.get("paging", {}).get("total", 0) or len(results)
        params["offset"] = params["offset"] + params["limit"]
        if params["offset"] >= total:
            break
    return results


def fmt_brl(value):
    return f"R${value:>8.2f}"


def cmd_payments(date_from=None, date_to=None):
    params = {
        "sort": "date_approved",
        "criteria": "desc",
        "limit": 50,
    }
    if date_from:
        params["begin_date"] = date_from + "T00:00:00.000-03:00"
        params["end_date"] = (date_to or date_from) + "T23:59:59.999-03:00"

    payments = fetch_all("/v1/payments/search", params)
    approved = [p for p in payments if p.get("status") == "approved"]

    print(f"Total payments: {len(payments)}  Approved: {len(approved)}\n")

    for p in approved:
        amt = float(p.get("transaction_amount", 0))
        net = float(p.get("net_amount", 0))
        date = p.get("date_approved", p.get("date_created", "?"))[:10]
        desc = p.get("description") or "(no description)"
        method = p.get("payment_method_id", "?")
        installments = p.get("installments", 1)
        card_id = (p.get("card", {}) or {}).get("id", "?")
        print(
            f"  [{date}] {fmt_brl(amt):>10} "
            f"{desc[:50]:50} "
            f"{method:>8} "
            f"{installments:>2}x "
            f"net={fmt_brl(net)}"
        )

    total_amt = sum(float(p.get("transaction_amount", 0)) for p in approved)
    total_net = sum(float(p.get("net_amount", 0)) for p in approved)
    total_fees = total_amt - total_net
    print(f"\n  Total: {fmt_brl(total_amt)}  Fees: {fmt_brl(total_fees)}  "
          f"Net: {fmt_brl(total_net)}")


def cmd_movements(date_from=None, date_to=None):
    params = {
        "range": "date_of_creation",
        "limit": 50,
    }
    if date_from:
        params["begin_date"] = date_from + "T00:00:00.000-03:00"
        params["end_date"] = (date_to or date_from) + "T23:59:59.999-03:00"

    movs = fetch_all("/v1/mercadopagoaccount/movements/search", params)

    print(f"Account movements: {len(movs)}\n")

    total_in = 0
    total_out = 0
    for m in movs:
        amt = abs(float(m.get("amount", 0)))
        mtype = m.get("type", "?")
        desc = m.get("description", "")
        date = (m.get("date_of_creation") or "?")[:10]
        net = float(m.get("net_amount", 0))
        fee = float(m.get("fee_amount", 0))
        if net > 0:
            total_in += net
            sign = "+"
        else:
            total_out += abs(net)
            sign = "-"
        print(
            f"  [{date}] {sign}{fmt_brl(abs(net)):>10} "
            f"{desc[:50]:50} "
            f"fee={fmt_brl(fee)}"
        )

    print(f"\n  In: {fmt_brl(total_in)}  Out: {fmt_brl(total_out)}  "
          f"Net: {fmt_brl(total_in - total_out)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__.strip())
        sys.exit(1)

    cmd = sys.argv[1]
    date_from = sys.argv[2] if len(sys.argv) > 2 else None
    date_to = sys.argv[3] if len(sys.argv) > 3 else None

    if cmd == "payments":
        cmd_payments(date_from, date_to)
    elif cmd == "movements":
        cmd_movements(date_from, date_to)
    else:
        print(__doc__.strip())
