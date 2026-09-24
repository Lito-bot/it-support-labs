# ENG-2042 — Daily report does a full table scan: missing index on shipments(customer_id, created_at)

| Field | Value |
|---|---|
| **Type** | Bug (performance) |
| **Severity** | High for large accounts — `GET /v1/reports/daily` always times out |
| **Component** | API / reports, database schema |
| **Reported from** | Support ticket [PS-1007](PS-1007-report-timeout.md) (MegaEnvíos) |

## Summary

The daily report filters `shipments` by `customer_id` and a `created_at` range. There is no index covering those columns, so Postgres does a parallel sequential scan of the whole table on every call. For an account with ~8M shipments that is ~160 ms against a 150 ms budget, so the request is always cancelled (504). Small accounts are unaffected, which is why it looked customer-specific.

## Steps to reproduce

`GET /v1/reports/daily?from=<today-6d>&to=<today>` with the MegaEnvíos read key → `504 report_timeout`. Script: [`scenarios/ps-1007-report-timeout.sh`](../scenarios/ps-1007-report-timeout.sh). Automated: `pytest tests/test_reports.py -k indexed` (currently `xfail`, strict).

## Evidence

| | Plan | Execution time |
|---|---|---|
| **Current** | Parallel Seq Scan, 2.6M rows removed by filter per worker | ~159 ms (API: cancelled at 150 ms, 504) |
| **With index** (tested in a rolled-back transaction) | Index Only Scan, 0 heap fetches | ~23 ms |

Full plans: [`evidence/ps-1007-report-timeout.txt`](../evidence/ps-1007-report-timeout.txt)

## Suggested fix

```sql
CREATE INDEX CONCURRENTLY shipments_customer_created ON shipments (customer_id, created_at);
```

- `CONCURRENTLY` so the live table isn't locked during the build.
- Add the index to `schema.sql` so new environments get it, and remove the `xfail` marker.
- Optional: update the 504 message. "Try a shorter date range" doesn't help when the cost comes from table size.

## Workaround given to the customer

Aggregate from `GET /v1/shipments` pages on their side until the fix ships.
