"""One JSON object per log line, always carrying the request id.

Support finds a customer's request by the X-Request-Id they send in, so every
line written while handling that request has to include it.
"""
import contextvars
import json
import sys
from datetime import datetime, timezone

request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")


def log(event: str, **fields) -> None:
    record = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "event": event,
        "request_id": request_id_var.get(),
        **fields,
    }
    sys.stdout.write(json.dumps(record, ensure_ascii=False, default=str) + "\n")
    sys.stdout.flush()
