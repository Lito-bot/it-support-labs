# PS-1004 — "Your API blocks us every night"

> Reproduced in the lab: [`scenarios/ps-1004-rate-limit.sh`](../scenarios/ps-1004-rate-limit.sh) → [`evidence/ps-1004-rate-limit.txt`](../evidence/ps-1004-rate-limit.txt)

| Field | Value |
|---|---|
| **Customer** | Litoral Bikes (growth plan) |
| **Priority** | P3 — nightly job incomplete, no data loss |
| **Channel** | Email, somewhat frustrated |
| **Outcome** | Customer-side retry logic; limit explained |

## Customer message

> "Every night our sync script gets hundreds of 429 errors and half our orders don't update. This started when we grew. Are you throttling us on purpose?"

## Investigation

1. Reproduced their pattern: requests back to back with no pause. The first 10 get 200, the next ones 429.
2. The 429 response tells the client exactly what to do:

   ```
   HTTP/1.1 429 Too Many Requests
   retry-after: 10
   {"error": "rate_limited", "retry_after_s": 10, "message": "Too many requests for this API key. Retry after 10s."}
   ```

3. API log: `rate_limited` events for `cus_litoral`, one per rejected request. The limit is per API key (10 requests per 10 seconds in this lab), the same for every customer on the plan. They are not being singled out.
4. A client that reads `Retry-After`, waits, and retries gets 200 on the next call.

**Root cause:** their sync has no backoff. When the order volume grew, the burst went over the limit, and they treat 429 as a permanent failure instead of "wait and retry".

## Reply to the customer

> Hi! You're not being singled out. Every API key has the same limit, and your nightly sync is going over it because it sends requests back to back. As your order volume grew, the burst got bigger than the limit.
>
> The good news is it's an easy fix, and no orders were lost: the requests that got 429 were never processed, so it's safe to retry them. Every 429 response includes a `Retry-After` header with the number of seconds to wait. If the script waits that long and retries, the sync will complete. I tested exactly that on our side.
>
> Two things that help even more: add a short pause between requests, and use `limit=100` on list calls so you need fewer requests overall. If you think you need a higher limit for your volume, tell me roughly how many orders you sync per night and I'll check the options on your plan.

**Tags:** `api` `rate-limiting` `429` `retry-after` `backoff`
