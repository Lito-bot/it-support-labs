#!/usr/bin/env bash
# PS-1005 - "We receive the same shipment update 3 times." (Sur Market)
# Their webhook handler calls their ERP before replying, which takes ~4s.
source "$(dirname "$0")/lib.sh"
W=$(key cus_sur write_key)
echo '{"delay_seconds": 4}' > shared/customer-sim.json

step "Create one shipment"
out=$(curl -s "$API/v1/shipments" -H "Authorization: Bearer $W" -H 'Content-Type: application/json' \
  -d '{"recipient_city":"Rosario","weight_kg":1.1}')
echo "$out"
tracking=$(sed -E 's/.*"tracking_code":"([^"]+)".*/\1/' <<<"$out")
echo "(waiting for deliveries and retries...)"; sleep 16

step "Customer side: how many times their handler applied it"
curl -s "$SHOP/processed" | grep -o "\"tracking_code\":\"$tracking\"" | wc -l | sed 's/^ */times processed: /'
shop_log "$tracking"

step "Parcelo side: delivery attempts for that event"
event=$(docker compose exec -T db psql -U parcelo -d parcelo -tAc \
  "SELECT id FROM events WHERE payload->'data'->>'tracking_code' = '$tracking'")
req docker compose exec -T db psql -U parcelo -d parcelo -c \
  "SELECT attempt, status_code, error, duration_ms FROM webhook_deliveries WHERE event_id = '$event' ORDER BY attempt"

echo '{"delay_seconds": 0}' > shared/customer-sim.json
