# PS-1005 — "We get every webhook three times"

> Reproduced in the lab: [`scenarios/ps-1005-duplicate-webhooks.sh`](../scenarios/ps-1005-duplicate-webhooks.sh) → [`evidence/ps-1005-duplicate-webhooks.txt`](../evidence/ps-1005-duplicate-webhooks.txt)

| Field | Value |
|---|---|
| **Customer** | Sur Market (growth plan) |
| **Priority** | P2 — duplicate stock movements in their ERP |
| **Channel** | Phone call, then email |
| **Outcome** | Working as designed (at-least-once delivery); customer-side fix guided |

## Customer message

> "Since Monday every shipment.created webhook arrives 3 times and our ERP books the order 3 times. Your system is sending duplicates."

## Investigation

1. **Customer side** (their handler log): the same event was applied three times, about 4–5 seconds apart. Same `event_id` every time:

   ```
   23:32:22  order_updated  evt_676c7dd1a34e2ad7  PCL08000125
   23:32:26  order_updated  evt_676c7dd1a34e2ad7  PCL08000125
   23:32:31  order_updated  evt_676c7dd1a34e2ad7  PCL08000125
   ```

2. **Our side**, delivery attempts for that event:

   ```
    attempt | status_code |  error  | duration_ms
          1 |             | timeout |        3005
          2 |             | timeout |        3004
          3 |             | timeout |        3004
   ```

   Their endpoint never answered within our 3-second timeout, so from our side every attempt failed and was retried. From theirs, every attempt **was processed**: their handler does the ERP update first and only replies afterwards, which takes about 4 seconds. (Worth asking them what changed around Monday: the timing points at their ERP call getting slower, not at anything on our side.)

3. The duplicates are the retry mechanism working as intended. Webhooks are delivered **at least once**: if we can't confirm delivery, we send it again. That is why every delivery carries the same `Parcelo-Event-Id`.

## Reply to the customer

> Hi! I found what's going on, and there's a quick fix on your side.
>
> Your webhook endpoint is taking about 4 seconds to reply, and we wait 3. When we don't get an answer in time we assume it didn't arrive and send it again, up to 3 times. Your system *is* receiving and processing each one, it just answers too late, so the order gets booked three times.
>
> Two changes fix it for good:
> 1. **Reply first, process after.** Return 200 as soon as you've received and verified the webhook, then do the ERP update in the background.
> 2. **Ignore repeats.** Every delivery of the same event has the same `Parcelo-Event-Id` header. If you save the ids you've processed and skip ones you've already seen, a retry can never double-book anything, even if it happens for another reason.
>
> The second one is the important one, because retries can always happen (a network blip, a deploy on your side). For the orders already duplicated, the three copies of each event share an id, so you can find them by that.

## Follow-up (internal)

- Our retries aren't wrong, but the dashboard shows these deliveries as "failed" while the customer did get them, which is confusing. Suggested to product: show the timeout reason and document the 3-second limit next to the webhook settings.

**Tags:** `webhooks` `retries` `idempotency` `timeouts` `at-least-once`
