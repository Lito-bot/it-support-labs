#!/usr/bin/env bash
# PS-1001 - "Our API key doesn't work, we get 401." (Andes Deco)
# Their integration reads API_KEY="pcl_live_..." from a .env file and keeps the quotes.
source "$(dirname "$0")/lib.sh"
K=$(key cus_andes write_key)

step "Reproduce what the customer sends (key wrapped in quotes)"
req curl -s -i "$API/v1/shipments" -H "Authorization: Bearer \"$K\""
rid=$(request_id_of "$OUT")

step "Look up their request id ($rid) in the API logs"
api_log "$rid"

step "Same key without the quotes"
req curl -s -o /dev/null -w 'HTTP %{http_code}\n' "$API/v1/shipments" -H "Authorization: Bearer $K"
