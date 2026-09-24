"""PS-1003 (comma decimal), PS-1004 (rate limit), PS-1008 (pagination)."""
from conftest import bearer, make_key
from parcelo import config, db


def test_create_shipment(client):
    r = client.post("/v1/shipments", headers=bearer(make_key()),
                    json={"recipient_city": "Mendoza", "weight_kg": 2.5})
    assert r.status_code == 201
    body = r.json()
    assert body["tracking_code"].startswith("PCL")
    assert body["weight_kg"] == 2.5


def test_comma_decimal_weight_is_rejected_with_field_name(client):
    r = client.post("/v1/shipments", headers=bearer(make_key()),
                    json={"recipient_city": "Mendoza", "weight_kg": "2,5"})
    assert r.status_code == 422
    assert "weight_kg" in r.text


def test_rate_limit_returns_429_with_retry_after(client):
    h = bearer(make_key(scope="read"))
    codes = [client.get("/v1/shipments", headers=h).status_code for _ in range(config.RATE_LIMIT_REQUESTS)]
    assert set(codes) == {200}
    r = client.get("/v1/shipments", headers=h)
    assert r.status_code == 429
    assert r.json()["error"] == "rate_limited"
    assert 1 <= int(r.headers["Retry-After"]) <= config.RATE_LIMIT_WINDOW_S


def test_rate_limit_is_per_key(client):
    a, b = bearer(make_key(scope="read")), bearer(make_key(scope="read"))
    for _ in range(config.RATE_LIMIT_REQUESTS):
        client.get("/v1/shipments", headers=a)
    assert client.get("/v1/shipments", headers=a).status_code == 429
    assert client.get("/v1/shipments", headers=b).status_code == 200


def _insert_shipments(customer_id: str, n: int) -> None:
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO shipments (customer_id, tracking_code, recipient_city, weight_kg) "
            "SELECT %s, 'PCL' || g, 'Rosario', 1 FROM generate_series(1, %s) g",
            (customer_id, n))


def test_pagination_returns_next_cursor(client):
    _insert_shipments("cus_test", 60)
    h = bearer(make_key(scope="read"))
    first = client.get("/v1/shipments", headers=h).json()
    assert len(first["data"]) == config.PAGE_SIZE_DEFAULT
    assert first["has_more"] is True
    second = client.get("/v1/shipments", headers=h, params={"cursor": first["next_cursor"]}).json()
    assert len(second["data"]) == 10
    assert second["has_more"] is False
    ids = [s["id"] for s in first["data"] + second["data"]]
    assert len(set(ids)) == 60
    assert client.get("/v1/shipments/count", headers=h).json()["total"] == 60


def test_customers_only_see_their_own_shipments(client):
    _insert_shipments("cus_other", 5)
    r = client.get("/v1/shipments", headers=bearer(make_key(scope="read")))
    assert r.json()["data"] == []


def test_bad_cursor_is_400(client):
    r = client.get("/v1/shipments", headers=bearer(make_key(scope="read")), params={"cursor": "not-a-cursor"})
    assert r.status_code == 400
