"""First-boot lab data: five customer shops, their API keys and one webhook endpoint.

Keys and the webhook secret are generated fresh and written to
/shared/lab-keys.json (git-ignored), which the scenario scripts and the
customer simulator read. Nothing secret is committed to the repo.
"""
import json
import os
import secrets
from pathlib import Path

from . import auth, config, db
from .logs import log

CUSTOMERS = [
    ("cus_andes", "Andes Deco", "starter"),        # PS-1001, PS-1008
    ("cus_pampa", "Pampa Outdoor", "growth"),      # PS-1002, PS-1003
    ("cus_litoral", "Litoral Bikes", "growth"),    # PS-1004
    ("cus_sur", "Sur Market", "growth"),           # PS-1005, PS-1006
    ("cus_mega", "MegaEnvíos", "enterprise"),      # PS-1007
]
KEYS = [("cus_andes", "write"), ("cus_pampa", "read"), ("cus_pampa", "write"),
        ("cus_litoral", "read"), ("cus_sur", "write"), ("cus_mega", "read")]


def run_if_enabled() -> None:
    if os.environ.get("SEED_ON_STARTUP") != "1":
        return
    with db.connect() as conn:
        if conn.execute("SELECT count(*) AS n FROM customers").fetchone()["n"]:
            return
        keys = _seed(conn)
    Path(config.SHARED_DIR, "lab-keys.json").write_text(json.dumps(keys, indent=2), encoding="utf-8")
    log("seed_complete", customers=len(CUSTOMERS), bulk_shipments=config.BULK_SHIPMENTS)


def _seed(conn) -> dict:
    keys: dict = {}
    for cid, name, plan in CUSTOMERS:
        conn.execute("INSERT INTO customers (id, name, plan) VALUES (%s, %s, %s)", (cid, name, plan))
        keys[cid] = {}
    for cid, scope in KEYS:
        keys[cid][f"{scope}_key"] = auth.create_api_key(conn, cid, scope)

    secret = "whsec_" + secrets.token_hex(16)
    conn.execute("INSERT INTO webhook_endpoints (customer_id, url, secret) VALUES (%s, %s, %s)",
                 ("cus_sur", "http://customer:8000/webhooks/parcelo", secret))
    keys["cus_sur"]["webhook_secret"] = secret

    # Andes Deco has 60 shipments: more than one page (PS-1008).
    conn.execute(
        "INSERT INTO shipments (customer_id, tracking_code, recipient_city, weight_kg, status, created_at) "
        "SELECT 'cus_andes', 'PCL' || lpad(g::text, 8, '0'), 'Mendoza', 1.5, 'delivered', now() - g * interval '6 hours' "
        "FROM generate_series(1, 60) g")
    # MegaEnvíos has two years of history (PS-1007).
    conn.execute(
        "INSERT INTO shipments (customer_id, recipient_city, weight_kg, status, created_at) "
        "SELECT 'cus_mega', 'Buenos Aires', 1 + (g %% 20), 'delivered', now() - random() * interval '730 days' "
        "FROM generate_series(1, %s) g", (config.BULK_SHIPMENTS,))
    conn.execute("ANALYZE shipments")
    return keys
