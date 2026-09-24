#!/usr/bin/env bash
# PS-1002 - "We can list shipments but creating one gives 403." (Pampa Outdoor)
source "$(dirname "$0")/lib.sh"
R=$(key cus_pampa read_key); W=$(key cus_pampa write_key)
BODY='{"recipient_city":"Bariloche","weight_kg":3.2}'

step "Create with the key their integration uses"
req curl -s -i -X POST "$API/v1/shipments" -H "Authorization: Bearer $R" -H 'Content-Type: application/json' -d "$BODY"
api_log "$(request_id_of "$OUT")"

step "Which keys does this customer have? (support DB console, prefixes only)"
req docker compose exec -T db psql -U parcelo -d parcelo -c \
  "SELECT key_prefix, scope, revoked, created_at::date FROM api_keys WHERE customer_id = 'cus_pampa' ORDER BY id"

step "Same request with their write-scoped key"
req curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X POST "$API/v1/shipments" -H "Authorization: Bearer $W" -H 'Content-Type: application/json' -d "$BODY"
