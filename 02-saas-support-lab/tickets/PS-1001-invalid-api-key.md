# PS-1001 — "Our API key doesn't work"

> Reproduced in the lab: [`scenarios/ps-1001-invalid-key.sh`](../scenarios/ps-1001-invalid-key.sh) → [`evidence/ps-1001-invalid-key.txt`](../evidence/ps-1001-invalid-key.txt)

| Field | Value |
|---|---|
| **Customer** | Andes Deco (starter plan) |
| **Priority** | P2 — integration fully blocked |
| **Channel** | Email, with a screenshot of the error |
| **Outcome** | Customer-side config issue, solved in one reply |

## Customer message

> "We just finished our integration and every call returns 401 invalid_api_key. We copied the key straight from the dashboard. Request id from the last try: req_0221c55bff3a"

## Investigation

1. **Start from the request id they sent**, not from guesses. The API log line for it:

   ```json
   {"event": "auth_failed", "request_id": "req_0221c55bff3a", "reason": "invalid_api_key", "client_ip": "172.18.0.1",
    "key_prefix": "\"pcl_live_cc", "key_length": 35, "expected_length": 33}
   ```

2. Two details give it away: the key is **2 characters longer** than any valid key, and the logged prefix **starts with a `"`**. The key they're sending is wrapped in quotation marks. That usually comes from a `.env` file like `API_KEY="pcl_live_..."` read by a loader that keeps the quotes.
3. Confirmed by reproducing both ways: with quotes → 401, same key without quotes → 200.

The log never contains the full key, only the first 12 characters and the length. That is enough to diagnose this without anyone handling the customer's secret.

## Reply to the customer

> Hi! Thanks for including the request id, it made this quick to find.
>
> Your key is reaching us with quotation marks around it, so it's 35 characters instead of 33 and doesn't match. That usually happens when the key is stored in a `.env` file as `API_KEY="pcl_live_..."` and the loader keeps the quotes. If you remove the quotes in the file (or strip them in code) the same key will work. We tested it on our side and it returns 200 without them.
>
> The header should look exactly like `Authorization: Bearer pcl_live_...`. Let me know if it's still failing and send me the new request id.

## Follow-up (internal)

- Suggested to product: detect a key wrapped in quotes and say so in the 401 message. This is a common mistake and a better error would avoid the ticket entirely.

**Tags:** `api` `authentication` `401` `logs` `request-id`
