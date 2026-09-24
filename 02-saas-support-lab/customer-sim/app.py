"""Sur Market's webhook receiver: the *customer's* code, not Parcelo's.

It verifies the signature the way Parcelo's docs describe, applies the event,
and only then answers. It has two realistic flaws that tickets PS-1005 and
PS-1006 turn on:
  * it does its work before replying, so a slow reply still means "processed";
  * it doesn't remember event ids, so a retried delivery is applied twice.
"""
import hashlib
import hmac
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request, Response

SHARED = Path("/shared")
app = FastAPI()
processed: list[dict] = []


def log(event: str, **fields) -> None:
    rec = {"ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"), "event": event, **fields}
    sys.stdout.write(json.dumps(rec, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _secret() -> str:
    return json.loads((SHARED / "lab-keys.json").read_text(encoding="utf-8"))["cus_sur"]["webhook_secret"]


def _delay_seconds() -> float:
    settings = SHARED / "customer-sim.json"
    if not settings.exists():
        return 0.0
    return float(json.loads(settings.read_text(encoding="utf-8")).get("delay_seconds", 0))


def _valid_signature(header: str, body: bytes) -> bool:
    try:
        parts = dict(p.split("=", 1) for p in header.split(","))
        signed = f"{parts['t']}.".encode() + body
    except (KeyError, ValueError):
        return False
    expected = hmac.new(_secret().encode(), signed, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, parts["v1"])


@app.post("/webhooks/parcelo")
async def receive(request: Request) -> Response:
    body = await request.body()
    event_id = request.headers.get("Parcelo-Event-Id", "?")
    if not _valid_signature(request.headers.get("Parcelo-Signature", ""), body):
        log("signature_mismatch", event_id=event_id, body_bytes=len(body))
        return Response(status_code=400)
    event = json.loads(body)
    processed.append({"event_id": event_id, "type": event["type"], "tracking_code": event["data"].get("tracking_code")})
    log("order_updated", event_id=event_id, type=event["type"], tracking_code=event["data"].get("tracking_code"))
    time.sleep(_delay_seconds())   # e.g. a slow ERP call made before replying
    return Response(status_code=200)


@app.get("/processed")
def list_processed() -> list[dict]:
    return processed
