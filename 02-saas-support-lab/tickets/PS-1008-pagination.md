# PS-1008 — "Your dashboard says 60 shipments, the API gives us 50"

> Reproduced in the lab: [`scenarios/ps-1008-pagination.sh`](../scenarios/ps-1008-pagination.sh) → [`evidence/ps-1008-pagination.txt`](../evidence/ps-1008-pagination.txt)

| Field | Value |
|---|---|
| **Customer** | Andes Deco (starter plan) |
| **Priority** | P3 — their report is missing orders |
| **Channel** | Chat |
| **Outcome** | How pagination works; customer-side change |

## Customer message

> "The dashboard shows 60 shipments this month but GET /v1/shipments only returns 50. Are 10 missing? We're worried about data loss."

## Investigation

```
GET /v1/shipments/count           → {"total": 60}
GET /v1/shipments                 → 50 items, "has_more": true, "next_cursor": "aWQ6MTEw"
GET /v1/shipments?cursor=aWQ6MTEw → 10 items, "has_more": false
```

No data is missing. The list is paginated (50 per page by default), and their integration reads only the first page. The response says there's more (`has_more: true`) and how to get it (`next_cursor`).

The first thing to do with "we're worried about data loss" is confirm there isn't any, and say so in the first line of the reply.

## Reply to the customer

> Hi! Good news first: nothing is missing, all 60 shipments are there.
>
> The list comes in pages of 50. Your integration is reading only the first page. Each response has `"has_more": true` when there are more results and a `next_cursor` value. To get the rest, call the same URL again with `?cursor=<that value>` and repeat until `has_more` is `false`. I did that on your account: the second page has the other 10.
>
> If you'd rather make fewer calls, you can add `limit=100` (the maximum) to get up to 100 per page.

**Tags:** `api` `pagination` `cursor` `data-integrity`
