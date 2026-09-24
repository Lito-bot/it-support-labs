"""API keys: generated once, stored only as a sha256 hash, looked up by hash.

Failed lookups are logged with the key's first characters and its length.
That is enough for support to spot "pasted with quotes" or "truncated"
without the full key ever reaching a log file.
"""
import hashlib
import secrets
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request

from . import db
from .logs import log
from .ratelimit import limiter

KEY_PREFIX = "pcl_live_"
KEY_LENGTH = len(KEY_PREFIX) + 24
LOG_PREFIX_CHARS = 12


@dataclass(frozen=True)
class Caller:
    customer_id: str
    scope: str
    key_prefix: str
    key_hash: str


def hash_key(key: str) -> str:
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def create_api_key(conn, customer_id: str, scope: str) -> str:
    key = KEY_PREFIX + secrets.token_hex(12)
    conn.execute(
        "INSERT INTO api_keys (customer_id, key_prefix, key_hash, scope) VALUES (%s, %s, %s, %s)",
        (customer_id, key[:LOG_PREFIX_CHARS], hash_key(key), scope))
    return key


def _reject(request: Request, error: str, message: str, **log_fields):
    client = request.client.host if request.client else "unknown"
    log("auth_failed", reason=error, path=request.url.path, client_ip=client, **log_fields)
    # Failed attempts are limited per client address, so keys can't be guessed at full speed.
    wait = limiter.check(f"auth-failures:{client}")
    if wait is not None:
        raise HTTPException(status_code=429, headers={"Retry-After": str(wait)}, detail={
            "error": "rate_limited", "retry_after_s": wait, "message": "Too many failed authentication attempts."})
    raise HTTPException(status_code=401, detail={"error": error, "message": message})


def authenticate(request: Request) -> Caller:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        _reject(request, "missing_api_key", "Send your API key as 'Authorization: Bearer <key>'.")
    key = header[len("Bearer "):]
    with db.connect() as conn:
        row = conn.execute(
            "SELECT customer_id, scope, key_prefix, revoked FROM api_keys WHERE key_hash = %s",
            (hash_key(key),)).fetchone()
    if row is None:
        _reject(request, "invalid_api_key", "The API key provided is not valid.",
                key_prefix=key[:LOG_PREFIX_CHARS], key_length=len(key), expected_length=KEY_LENGTH)
    if row["revoked"]:
        _reject(request, "revoked_api_key", "This API key has been revoked.",
                key_prefix=row["key_prefix"], customer_id=row["customer_id"])
    caller = Caller(row["customer_id"], row["scope"], row["key_prefix"], hash_key(key))
    request.state.caller = caller
    wait = limiter.check(caller.key_hash)
    if wait is not None:
        log("rate_limited", customer_id=caller.customer_id, key_prefix=caller.key_prefix, retry_after_s=wait)
        raise HTTPException(status_code=429, headers={"Retry-After": str(wait)}, detail={
            "error": "rate_limited", "retry_after_s": wait,
            "message": f"Too many requests for this API key. Retry after {wait}s."})
    return caller


def require_write(caller: Caller = Depends(authenticate)) -> Caller:
    if caller.scope != "write":
        log("scope_denied", customer_id=caller.customer_id, key_prefix=caller.key_prefix, key_scope=caller.scope)
        raise HTTPException(status_code=403, detail={
            "error": "insufficient_scope", "required_scope": "write", "key_scope": caller.scope,
            "message": "This API key is read-only. Create a key with write scope in Settings > API keys."})
    return caller
