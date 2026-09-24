import os

# Must be set before the app modules read their config.
os.environ.setdefault("DATABASE_URL", "postgresql://parcelo:parcelo@db:5432/parcelo_test")
os.environ["BULK_SHIPMENTS"] = "0"
os.environ["SEED_ON_STARTUP"] = "0"
os.environ["WEBHOOK_BACKOFF_S"] = "0"

import pytest
from fastapi.testclient import TestClient

from parcelo import auth, db, ratelimit
from parcelo.main import app

CUSTOMERS = [("cus_test", "Test Shop", "starter"), ("cus_other", "Other Shop", "starter")]


@pytest.fixture(autouse=True)
def clean_db():
    db.apply_schema()
    with db.connect() as conn:
        conn.execute("TRUNCATE webhook_deliveries, events, webhook_endpoints, shipments, api_keys, customers RESTART IDENTITY CASCADE")
        for c in CUSTOMERS:
            conn.execute("INSERT INTO customers (id, name, plan) VALUES (%s, %s, %s)", c)
    ratelimit.limiter.reset()
    yield


@pytest.fixture
def client():
    return TestClient(app)


def make_key(customer_id="cus_test", scope="write", revoked=False) -> str:
    with db.connect() as conn:
        key = auth.create_api_key(conn, customer_id, scope)
        if revoked:
            conn.execute("UPDATE api_keys SET revoked = true WHERE key_hash = %s", (auth.hash_key(key),))
    return key


def bearer(key: str) -> dict:
    return {"Authorization": f"Bearer {key}"}
