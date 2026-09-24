"""Outgoing webhooks: signed, delivered at least once, every attempt recorded.

Signature header: Parcelo-Signature: t=<unix ts>,v1=<hex HMAC-SHA256 of "<t>." + raw body>
Receivers must verify against the raw body and de-duplicate on Parcelo-Event-Id.
"""
import hashlib
import hmac
import json
import secrets
import time
from datetime import datetime, timezone

import httpx
from psycopg.types.json import Jsonb

from . import config, db
from .logs import log

transport: httpx.BaseTransport | None = None   # tests swap in httpx.MockTransport


def sign(secret: str, timestamp: int, payload: bytes) -> str:
    return hmac.new(secret.encode(), f"{timestamp}.".encode() + payload, hashlib.sha256).hexdigest()


def record_event(conn, customer_id: str, event_type: str, data: dict) -> dict:
    event = {
        "id": "evt_" + secrets.token_hex(8),
        "type": event_type,
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "data": data,
    }
    conn.execute("INSERT INTO events (id, customer_id, type, payload) VALUES (%s, %s, %s, %s)",
                 (event["id"], customer_id, event_type, Jsonb(event)))
    return event


def _record_attempt(event_id: str, attempt: int, status: int | None, ms: int, error: str | None) -> None:
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO webhook_deliveries (event_id, attempt, status_code, duration_ms, error) VALUES (%s, %s, %s, %s, %s)",
            (event_id, attempt, status, ms, error))


def deliver(customer_id: str, event: dict) -> None:
    with db.connect() as conn:
        endpoint = conn.execute("SELECT url, secret FROM webhook_endpoints WHERE customer_id = %s",
                                (customer_id,)).fetchone()
    if endpoint is None:
        return
    body = json.dumps(event, ensure_ascii=False).encode("utf-8")
    ts = int(time.time())
    # Deliberate lab defect (ticket PS-1006 / ENG-2041): the signature is computed over a
    # second serialization with json.dumps' default ensure_ascii=True, not over `body`.
    # Identical for ASCII-only payloads, different as soon as data contains "ó", "ñ", etc.
    signature = sign(endpoint["secret"], ts, json.dumps(event).encode("utf-8"))
    headers = {"Content-Type": "application/json", "Parcelo-Event-Id": event["id"],
               "Parcelo-Signature": f"t={ts},v1={signature}"}

    with httpx.Client(transport=transport, timeout=config.WEBHOOK_TIMEOUT_S) as client:
        for attempt in range(1, config.WEBHOOK_MAX_ATTEMPTS + 1):
            started = time.monotonic()
            try:
                r = client.post(endpoint["url"], content=body, headers=headers)
                status, error = r.status_code, None
            except httpx.TimeoutException:
                status, error = None, "timeout"
            except httpx.HTTPError as exc:
                status, error = None, type(exc).__name__
            ms = int((time.monotonic() - started) * 1000)
            _record_attempt(event["id"], attempt, status, ms, error)
            log("webhook_attempt", customer_id=customer_id, event_id=event["id"], attempt=attempt,
                status_code=status, error=error, duration_ms=ms)
            if status is not None and 200 <= status < 300:
                return
            if attempt < config.WEBHOOK_MAX_ATTEMPTS:
                time.sleep(config.WEBHOOK_BACKOFF_S * 2 ** (attempt - 1))
    log("webhook_gave_up", customer_id=customer_id, event_id=event["id"])
