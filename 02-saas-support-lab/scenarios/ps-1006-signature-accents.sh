#!/usr/bin/env bash
# PS-1006 - "Signature check fails on some webhooks, not all." (Sur Market)
source "$(dirname "$0")/lib.sh"
W=$(key cus_sur write_key)
echo '{"delay_seconds": 0}' > shared/customer-sim.json

# The body goes through a file: on Windows, passing "ó" as a command-line argument to
# curl re-encodes it to the legacy code page (1 byte) and the JSON arrives invalid.
create() {
  printf '{"recipient_city":"%s","weight_kg":1}' "$1" > shared/body.json
  curl -s "$API/v1/shipments" -H "Authorization: Bearer $W" -H 'Content-Type: application/json; charset=utf-8' \
    --data-binary @shared/body.json | sed -E 's/.*"tracking_code":"([^"]+)".*/\1/'
}

step "Two shipments, one city with an accent"
t1=$(create "Rosario"); t2=$(create "Córdoba"); echo "Rosario -> $t1   Córdoba -> $t2"
sleep 8

step "Customer's webhook log for those two shipments"
shop_log "$t1"
event2=$(docker compose exec -T db psql -U parcelo -d parcelo -tAc \
  "SELECT id FROM events WHERE payload->'data'->>'tracking_code' = '$t2'")
shop_log "$event2"

step "Parcelo delivery attempts for the Córdoba event"
req docker compose exec -T db psql -U parcelo -d parcelo -c \
  "SELECT attempt, status_code, error FROM webhook_deliveries WHERE event_id = '$event2' ORDER BY attempt"

step "Pattern check across all Sur Market events: failures vs non-ASCII payloads"
req docker compose exec -T db psql -U parcelo -d parcelo -c "
  SELECT (e.payload::text ~ '[^\x01-\x7F]') AS has_non_ascii,
         count(DISTINCT e.id) AS events,
         count(DISTINCT e.id) FILTER (WHERE d.status_code = 400) AS signature_rejected
  FROM events e JOIN webhook_deliveries d ON d.event_id = e.id
  WHERE e.customer_id = 'cus_sur' GROUP BY 1 ORDER BY 1"

step "Why: the two serializations of the same text"
req docker compose exec -T api python -c "
import json
city = {'recipient_city': 'Córdoba'}
print('body sent (UTF-8):    ', json.dumps(city, ensure_ascii=False).encode())
print('what gets signed:     ', json.dumps(city).encode())"

step "Failing test attached to the escalation"
req docker compose exec -T api pytest -q -p no:cacheprovider -rx tests/test_webhooks.py -k non_ascii
