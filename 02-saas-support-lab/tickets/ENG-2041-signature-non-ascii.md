# ENG-2041 — Webhook signature doesn't match body when payload contains non-ASCII characters

| Field | Value |
|---|---|
| **Type** | Bug |
| **Severity** | High — signed webhooks silently dropped by correctly implemented receivers |
| **Component** | Webhooks / delivery |
| **Reported from** | Support ticket [PS-1006](PS-1006-webhook-signature.md) (Sur Market) |
| **Reporter** | Support |

## Summary

`Parcelo-Signature` is computed over a different byte sequence than the request body we send. The two are equal for ASCII-only payloads and differ whenever the payload has a non-ASCII character (e.g. `recipient_city: "Córdoba"`). Receivers that follow our docs (HMAC over the raw body) reject those webhooks.

## Impact

- Any customer with accented city or recipient names (every Spanish/Portuguese-speaking market) loses those webhooks after 3 retries.
- Customers can't work around it without disabling signature verification, which we must not recommend.
- Known affected: Sur Market. Likely wider: needs a query over `webhook_deliveries` for 400 responses on events with non-ASCII payloads.

## Steps to reproduce

1. Register a webhook endpoint that verifies `HMAC-SHA256(secret, "<t>." + raw_body)` as documented.
2. `POST /v1/shipments` with `{"recipient_city": "Córdoba", "weight_kg": 1}`.
3. Receiver computes the HMAC over the body → does not match `v1`.
4. Same with `"Rosario"` → matches.

Automated: `pytest tests/test_webhooks.py -k non_ascii` (currently `xfail`, strict).

## Expected vs actual

| | |
|---|---|
| **Expected** | Signature computed over the exact bytes sent as the request body |
| **Actual** | Body serialized with `json.dumps(event, ensure_ascii=False)` (UTF-8 bytes); signature computed over a second `json.dumps(event)` with the default `ensure_ascii=True` (`ó` escapes) |

## Evidence

- Receiver log: `signature_mismatch evt_96bd37d78803ab2b` ×3, only on the Córdoba event.
- Pattern across the customer's events: 1/1 non-ASCII rejected, 0/4 ASCII rejected.
- Serialization comparison: [`evidence/ps-1006-signature-accents.txt`](../evidence/ps-1006-signature-accents.txt)
- Code: `app/parcelo/webhooks.py`, `deliver()`, where `signature = sign(..., json.dumps(event).encode(...))`.

## Suggested fix

Sign the `body` variable that is actually sent:

```python
signature = sign(endpoint["secret"], ts, body)
```

Then remove the `xfail` marker. After deploying, consider re-sending failed `shipment.*` events from the last N days for affected customers (they are in `events` with their original ids, so receivers that de-duplicate will handle them safely).

## Workaround given to the customer

Reconcile with `GET /v1/shipments` daily. Keep signature verification on.
