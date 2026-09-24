#!/usr/bin/env bash
# PS-1007 - "The daily report always times out for us." (MegaEnvíos, 8M shipments)
source "$(dirname "$0")/lib.sh"
R=$(key cus_mega read_key)
FROM=$(date -u -d '6 days ago' +%F); TO=$(date -u +%F)
Q="SELECT (created_at AT TIME ZONE 'UTC')::date AS day, count(*) FROM shipments
   WHERE customer_id = 'cus_mega' AND created_at >= '$FROM' AND created_at < '$TO'::date + 1 GROUP BY 1 ORDER BY 1"

step "Their request: last 7 days"
req curl -s -i "$API/v1/reports/daily?from=$FROM&to=$TO" -H "Authorization: Bearer $R"
api_log "$(request_id_of "$OUT")"

step "Does it happen to a small customer too? (Andes Deco, same endpoint)"
req curl -s -o /dev/null -w 'HTTP %{http_code} in %{time_total}s\n' "$API/v1/reports/daily?from=$FROM&to=$TO" \
  -H "Authorization: Bearer $(key cus_andes write_key)"

step "Query plan for MegaEnvíos (read-only EXPLAIN)"
req docker compose exec -T db psql -U parcelo -d parcelo -c "EXPLAIN (ANALYZE, BUFFERS) $Q"

step "Proposed fix, tested inside a transaction that is rolled back (nothing is changed)"
req docker compose exec -T db psql -U parcelo -d parcelo -c "
BEGIN;
CREATE INDEX shipments_customer_created ON shipments (customer_id, created_at);
EXPLAIN (ANALYZE) $Q;
ROLLBACK;"
