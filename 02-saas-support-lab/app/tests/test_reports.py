"""PS-1007 / ENG-2042 (slow daily report)."""
import pytest

from conftest import bearer, make_key
from parcelo import db


def test_daily_report_counts_by_day(client):
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO shipments (customer_id, recipient_city, weight_kg, created_at) VALUES "
            "('cus_test', 'Rosario', 1, '2026-09-01 10:00+00'), "
            "('cus_test', 'Rosario', 1, '2026-09-01 15:00+00'), "
            "('cus_test', 'Rosario', 1, '2026-09-02 09:00+00'), "
            "('cus_other', 'Rosario', 1, '2026-09-01 10:00+00')")
    r = client.get("/v1/reports/daily", headers=bearer(make_key(scope="read")),
                   params={"from": "2026-09-01", "to": "2026-09-02"})
    assert r.status_code == 200
    assert r.json()["days"] == [{"day": "2026-09-01", "shipments": 2}, {"day": "2026-09-02", "shipments": 1}]


def test_report_rejects_reversed_range(client):
    r = client.get("/v1/reports/daily", headers=bearer(make_key(scope="read")),
                   params={"from": "2026-09-05", "to": "2026-09-01"})
    assert r.status_code == 400


@pytest.mark.xfail(strict=True, reason="ENG-2042: no index on shipments(customer_id, created_at)")
def test_report_filter_is_indexed():
    with db.connect() as conn:
        defs = [r["indexdef"] for r in conn.execute(
            "SELECT indexdef FROM pg_indexes WHERE tablename = 'shipments'").fetchall()]
    assert any("(customer_id, created_at)" in d for d in defs)
