"""PS-1001 (bad key format) and PS-1002 (read-only key)."""
import json

from conftest import bearer, make_key


def test_valid_key_lists_shipments(client):
    r = client.get("/v1/shipments", headers=bearer(make_key(scope="read")))
    assert r.status_code == 200
    assert r.headers["X-Request-Id"].startswith("req_")


def test_missing_header_is_401(client):
    r = client.get("/v1/shipments")
    assert r.status_code == 401
    assert r.json()["error"] == "missing_api_key"


def test_key_pasted_with_quotes_is_401_and_logged_with_length(client, capsys):
    key = make_key()
    r = client.get("/v1/shipments", headers=bearer(f'"{key}"'))
    assert r.status_code == 401
    assert r.json()["error"] == "invalid_api_key"
    auth_lines = [json.loads(l) for l in capsys.readouterr().out.splitlines() if '"auth_failed"' in l]
    assert auth_lines, "auth failures must be logged"
    line = auth_lines[-1]
    assert line["key_length"] == len(key) + 2
    assert line["expected_length"] == len(key)
    assert line["key_prefix"] == f'"{key}'[:12]
    assert key not in json.dumps(line), "the full key must never be logged"


def test_revoked_key_is_401(client):
    r = client.get("/v1/shipments", headers=bearer(make_key(revoked=True)))
    assert r.status_code == 401
    assert r.json()["error"] == "revoked_api_key"


def test_read_only_key_cannot_create(client):
    r = client.post("/v1/shipments", headers=bearer(make_key(scope="read")),
                    json={"recipient_city": "Rosario", "weight_kg": 1.2})
    assert r.status_code == 403
    body = r.json()
    assert body["error"] == "insufficient_scope"
    assert body["required_scope"] == "write"
    assert body["key_scope"] == "read"


def test_failed_auth_is_rate_limited_per_client(client):
    from parcelo import config
    bad = bearer("pcl_live_" + "0" * 24)
    codes = [client.get("/v1/shipments", headers=bad).status_code for _ in range(config.RATE_LIMIT_REQUESTS + 1)]
    assert codes[:-1] == [401] * config.RATE_LIMIT_REQUESTS
    assert codes[-1] == 429, "guessing keys must not be unlimited"


def test_unexpected_error_returns_500_with_request_id(monkeypatch, capsys):
    from fastapi.testclient import TestClient
    from parcelo import main
    key = make_key(scope="read")
    monkeypatch.setattr(main, "_count", lambda customer_id: 1 / 0)
    r = TestClient(main.app, raise_server_exceptions=False).get("/v1/shipments/count", headers=bearer(key))
    assert r.status_code == 500
    assert r.json()["error"] == "internal_error"
    assert r.json()["request_id"] == r.headers["X-Request-Id"]
    assert '"unhandled_error"' in capsys.readouterr().out


def test_keys_are_stored_hashed(client):
    key = make_key()
    from parcelo import db
    with db.connect() as conn:
        rows = conn.execute("SELECT key_hash, key_prefix FROM api_keys").fetchall()
    assert all(key not in (r["key_hash"], r["key_prefix"]) for r in rows)
