#!/usr/bin/env bash
# PS-1003 - "The API rejects our weights, the error makes no sense." (Pampa Outdoor)
# Their spreadsheet export writes decimals the Argentine way: 2,5
source "$(dirname "$0")/lib.sh"
W=$(key cus_pampa write_key)

step "Their request"
req curl -s -w '\nHTTP %{http_code}\n' -X POST "$API/v1/shipments" -H "Authorization: Bearer $W" \
  -H 'Content-Type: application/json' -d '{"recipient_city":"Tandil","weight_kg":"2,5"}'

step "Same shipment with a decimal point and a JSON number"
req curl -s -w '\nHTTP %{http_code}\n' -X POST "$API/v1/shipments" -H "Authorization: Bearer $W" \
  -H 'Content-Type: application/json' -d '{"recipient_city":"Tandil","weight_kg":2.5}'
