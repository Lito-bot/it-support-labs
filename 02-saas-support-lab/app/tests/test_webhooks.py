"""PS-1005 (retries cause duplicates) and PS-1006 / ENG-2041 (signature bug)."""
import hashlib
import hmac

import httpx
import pytest

from conftest import bearer, make_key
from parcelo import db, webhooks

SECRET = "whsec_test_secret"


def _register_endpoint(customer_id="cus_test"):
    with db.connect() as conn:
        conn.execute("INSERT INTO webhook_endpoints (customer_id, url, secret) VALUES (%s, %s, %s)",
                     (customer_id, "http://customer.test/hook", SECRET))


def _customer_side_verify(request: httpx.Request) -> bool:
    """What the docs tell customers to do: HMAC the raw body exactly as received."""
    parts = dict(p.split("=", 1) for p in request.headers["Parcelo-Signature"].split(","))
    expected = hmac.new(SECRET.encode(), f"{parts['t']}.".encode() + request.content, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, parts["v1"])


@pytest.fixture
def captured(monkeypatch):
    seen = []

    def handler(request):
        seen.append(request)
        return httpx.Response(200)

    monkeypatch.setattr(webhooks, "transport", httpx.MockTransport(handler))
    return seen


def _create(client, city):
    return client.post("/v1/shipments", headers=bearer(make_key()),
                       json={"recipient_city": city, "weight_kg": 1})


def test_webhook_is_sent_on_create(client, captured):
    _register_endpoint()
    _create(client, "Rosario")
    assert len(captured) == 1
    assert captured[0].headers["Parcelo-Event-Id"].startswith("evt_")


def test_signature_verifies_for_ascii_payload(client, captured):
    _register_endpoint()
    _create(client, "Rosario")
    assert _customer_side_verify(captured[0])


@pytest.mark.xfail(strict=True, reason="ENG-2041: signature computed over ASCII-escaped JSON, body sent as UTF-8")
def test_signature_verifies_for_non_ascii_payload(client, captured):
    _register_endpoint()
    _create(client, "Córdoba")
    assert _customer_side_verify(captured[0])


def test_slow_endpoint_is_retried_with_the_same_event_id(client, monkeypatch):
    _register_endpoint()
    calls = []

    def handler(request):
        calls.append(request)
        if len(calls) == 1:
            raise httpx.ReadTimeout("customer endpoint too slow", request=request)
        return httpx.Response(200)

    monkeypatch.setattr(webhooks, "transport", httpx.MockTransport(handler))
    _create(client, "Rosario")
    assert len(calls) == 2
    assert calls[0].headers["Parcelo-Event-Id"] == calls[1].headers["Parcelo-Event-Id"]
    with db.connect() as conn:
        attempts = conn.execute("SELECT attempt, status_code, error FROM webhook_deliveries ORDER BY attempt").fetchall()
    assert [a["attempt"] for a in attempts] == [1, 2]
    assert attempts[0]["error"] == "timeout" and attempts[1]["status_code"] == 200


def test_no_endpoint_means_no_delivery(client, captured):
    _create(client, "Rosario")
    assert captured == []
