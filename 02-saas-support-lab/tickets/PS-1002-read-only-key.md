# PS-1002 — "We can read but can't create shipments"

> Reproduced in the lab: [`scenarios/ps-1002-read-only-key.sh`](../scenarios/ps-1002-read-only-key.sh) → [`evidence/ps-1002-read-only-key.txt`](../evidence/ps-1002-read-only-key.txt)

| Field | Value |
|---|---|
| **Customer** | Pampa Outdoor (growth plan) |
| **Priority** | P2 — can't create orders |
| **Channel** | Chat |
| **Outcome** | Configuration, solved in one reply |

## Customer message

> "Listing shipments works fine but POST /v1/shipments gives us 403. Did something change on your side?"

## Investigation

1. Reproduced their POST with the key their integration uses. Response:

   ```json
   {"error": "insufficient_scope", "required_scope": "write", "key_scope": "read", ...}
   ```

2. API log: `scope_denied ... key_prefix: pcl_live_375, key_scope: read`.
3. Their keys (support console shows **prefixes only**):

   ```
    key_prefix   | scope | revoked
    pcl_live_375 | read  | f        ← the one in their integration
    pcl_live_1a3 | write | f
   ```

   They have a write key already; the integration is configured with the read-only one. Nothing changed on our side: the 403 is the scope working as designed.
4. Same request with the write key → 201.

## Reply to the customer

> Hi! Nothing changed on our side. The key your integration uses (it starts with `pcl_live_375`) is a read-only key, so it can list shipments but not create them.
>
> Your account already has a key with write access, the one starting with `pcl_live_1a3`. If you swap that one into the integration, creating shipments will work. I tested the same request with it and it returns 201.
>
> If you'd rather keep separate keys, a common setup is the read-only key for dashboards and reports and the write key only on the server that creates orders.

**Tags:** `api` `authorization` `403` `scopes`
