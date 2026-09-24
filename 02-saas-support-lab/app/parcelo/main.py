"""Parcelo public API (v1)."""
import base64
import secrets
import time
import traceback
from contextlib import asynccontextmanager
from datetime import date, timedelta

import psycopg
from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import config, db, seed, webhooks
from .auth import Caller, authenticate, require_write
from .logs import log, request_id_var

@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.apply_schema()
    seed.run_if_enabled()
    yield


app = FastAPI(title="Parcelo API", version="1", lifespan=lifespan)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = "req_" + secrets.token_hex(6)
    request_id_var.set(request_id)
    started = time.monotonic()
    try:
        response = await call_next(request)
    except Exception as exc:
        # The customer still gets a request id to quote, and the traceback lands next to it in the log.
        log("unhandled_error", error=type(exc).__name__, traceback=traceback.format_exc())
        response = JSONResponse({"error": "internal_error", "message": "Something went wrong on our side.",
                                 "request_id": request_id}, status_code=500)
    caller = getattr(request.state, "caller", None)
    response.headers["X-Request-Id"] = request_id
    log("request", method=request.method, path=request.url.path, query=str(request.url.query) or None,
        status=response.status_code, duration_ms=int((time.monotonic() - started) * 1000),
        customer_id=caller.customer_id if caller else None, key_prefix=caller.key_prefix if caller else None)
    return response


@app.exception_handler(HTTPException)
async def http_error(request: Request, exc: HTTPException):
    body = exc.detail if isinstance(exc.detail, dict) else {"error": "http_error", "message": str(exc.detail)}
    return JSONResponse({**body, "request_id": request_id_var.get()}, status_code=exc.status_code,
                        headers=exc.headers)


class ShipmentIn(BaseModel):
    recipient_city: str = Field(min_length=1, max_length=120)
    weight_kg: float = Field(gt=0, le=1000)


def _row_out(row: dict) -> dict:
    """JSON-safe shipment: used for the API response and the webhook payload alike."""
    return {**row, "weight_kg": float(row["weight_kg"]),
            "created_at": row["created_at"].isoformat(), "updated_at": row["updated_at"].isoformat()}


def _encode_cursor(last_id: int) -> str:
    return base64.urlsafe_b64encode(f"id:{last_id}".encode()).decode()


def _decode_cursor(cursor: str) -> int:
    try:
        kind, value = base64.urlsafe_b64decode(cursor.encode()).decode().split(":")
        if kind != "id":
            raise ValueError
        return int(value)
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(400, detail={"error": "invalid_cursor", "message": "Use next_cursor from the previous page as-is."})


SHIPMENT_COLS = "id, tracking_code, recipient_city, weight_kg, status, created_at, updated_at"


@app.get("/v1/shipments")
def list_shipments(caller: Caller = Depends(authenticate), cursor: str | None = None,
                   limit: int = Query(config.PAGE_SIZE_DEFAULT, ge=1, le=config.PAGE_SIZE_MAX)) -> dict:
    after = _decode_cursor(cursor) if cursor else 0
    with db.connect() as conn:
        rows = conn.execute(
            f"SELECT {SHIPMENT_COLS} FROM shipments WHERE customer_id = %s AND id > %s ORDER BY id LIMIT %s",
            (caller.customer_id, after, limit + 1)).fetchall()
    page, has_more = rows[:limit], len(rows) > limit
    return {"data": [_row_out(r) for r in page], "has_more": has_more,
            "next_cursor": _encode_cursor(page[-1]["id"]) if has_more else None}


def _count(customer_id: str) -> int:
    with db.connect() as conn:
        return conn.execute("SELECT count(*) AS n FROM shipments WHERE customer_id = %s", (customer_id,)).fetchone()["n"]


@app.get("/v1/shipments/count")
def count_shipments(caller: Caller = Depends(authenticate)) -> dict:
    return {"total": _count(caller.customer_id)}


@app.post("/v1/shipments", status_code=201)
def create_shipment(body: ShipmentIn, background: BackgroundTasks, caller: Caller = Depends(require_write)) -> dict:
    with db.connect() as conn:
        row = conn.execute(
            "INSERT INTO shipments (customer_id, recipient_city, weight_kg) VALUES (%s, %s, %s) RETURNING id",
            (caller.customer_id, body.recipient_city, body.weight_kg)).fetchone()
        row = conn.execute(
            f"UPDATE shipments SET tracking_code = 'PCL' || lpad(id::text, 8, '0') WHERE id = %s RETURNING {SHIPMENT_COLS}",
            (row["id"],)).fetchone()
        event = webhooks.record_event(conn, caller.customer_id, "shipment.created", _row_out(row))
    background.add_task(webhooks.deliver, caller.customer_id, event)
    return _row_out(row)


@app.get("/v1/reports/daily")
def daily_report(caller: Caller = Depends(authenticate),
                 date_from: date = Query(alias="from"), date_to: date = Query(alias="to")) -> dict:
    if date_to < date_from:
        raise HTTPException(400, detail={"error": "invalid_range", "message": "'to' must not be before 'from'."})
    started = time.monotonic()
    try:
        with db.connect() as conn:
            conn.execute(f"SET statement_timeout = {int(config.REPORT_TIMEOUT_MS)}")
            rows = conn.execute(
                "SELECT (created_at AT TIME ZONE 'UTC')::date AS day, count(*) AS shipments FROM shipments "
                "WHERE customer_id = %s AND created_at >= %s AND created_at < %s GROUP BY 1 ORDER BY 1",
                (caller.customer_id, date_from, date_to + timedelta(days=1))).fetchall()
    except psycopg.errors.QueryCanceled:
        log("report_timeout", customer_id=caller.customer_id, timeout_ms=config.REPORT_TIMEOUT_MS,
            elapsed_ms=int((time.monotonic() - started) * 1000), date_from=date_from, date_to=date_to)
        raise HTTPException(504, detail={"error": "report_timeout",
                                         "message": "The report took too long. Try a shorter date range."})
    return {"days": [{"day": r["day"].isoformat(), "shipments": r["shipments"]} for r in rows]}
