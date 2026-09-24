# PS-1007 — "The daily report always times out for us"

> Reproduced in the lab: [`scenarios/ps-1007-report-timeout.sh`](../scenarios/ps-1007-report-timeout.sh) → [`evidence/ps-1007-report-timeout.txt`](../evidence/ps-1007-report-timeout.txt)
> **Escalated to engineering:** [ENG-2042](ENG-2042-report-missing-index.md)

| Field | Value |
|---|---|
| **Customer** | MegaEnvíos (enterprise plan, ~8M shipments) |
| **Priority** | P2 — enterprise customer, feature unusable |
| **Channel** | Account manager, forwarded |
| **Outcome** | **Product performance bug** — escalated with query plan and a tested fix; workaround given |

## Customer message

> "GET /v1/reports/daily returns 504 report_timeout every time, even for just the last 7 days. The message says to try a shorter range but 7 days is already short."

## Investigation

1. Reproduced their exact request → **504** `report_timeout`. API log: `timeout_ms: 150, elapsed_ms: 163`, so the query was cancelled at the report's time budget.
2. **Same endpoint, same range, small customer (Andes Deco): 200 in 0.02 s.** So the endpoint isn't down. The problem scales with the amount of data a customer has.
3. Query plan (read-only `EXPLAIN ANALYZE`) for MegaEnvíos:

   ```
   ->  Parallel Seq Scan on shipments  (actual time=6.7..123.3 rows=25495 loops=3)
         Filter: (created_at >= ... AND created_at < ... AND customer_id = 'cus_mega')
         Rows Removed by Filter: 2641193
   Execution Time: 159 ms
   ```

   To return about 76k rows for 7 days, Postgres reads the **entire 8M-row table** and throws away more than 99% of it. There is no index on `(customer_id, created_at)`, the two columns the report filters on. "Try a shorter range" can't help, because the scan cost doesn't depend on the range.

4. Tested the obvious fix **inside a transaction that was rolled back** (nothing changed):

   ```
   CREATE INDEX ... ON shipments (customer_id, created_at);
   ->  Index Only Scan using shipments_customer_created  (actual time=0.05..14.7 rows=76486)
   Execution Time: 23 ms        (was 159 ms, ~7x faster, well under the budget)
   ```

Support doesn't create indexes on production. That is a schema change for engineering to schedule (it needs `CREATE INDEX CONCURRENTLY` on a live table). The ticket gives them everything needed to do it quickly.

## Reply to the customer (via account manager)

> Hi! Thanks for the details. I was able to reproduce it. The report is slow for accounts with a large shipment history like yours, whatever date range you choose, so a shorter range unfortunately won't help. I've passed it to our engineering team with the cause and a tested fix.
>
> Until then, you can build the same numbers from `GET /v1/shipments` (use `limit=100` and follow `next_cursor`) and count by day on your side. I'll let you know as soon as the fix is deployed.

## Follow-up (internal)

- The 504 message ("Try a shorter date range") is misleading when the cause is table size. Suggested rewording once the index is in.

**Tags:** `api` `performance` `504` `postgresql` `explain` `index` `escalation`
