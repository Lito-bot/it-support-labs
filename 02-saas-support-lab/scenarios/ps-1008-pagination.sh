#!/usr/bin/env bash
# PS-1008 - "Your dashboard says 60 shipments but the API only gives us 50." (Andes Deco)
source "$(dirname "$0")/lib.sh"
K=$(key cus_andes write_key)

step "Count vs list"
req curl -s "$API/v1/shipments/count" -H "Authorization: Bearer $K"
page1=$(curl -s "$API/v1/shipments" -H "Authorization: Bearer $K")
echo "first page: $(grep -o '"tracking_code"' <<<"$page1" | wc -l) items, $(grep -o '"has_more":[a-z]*' <<<"$page1"), $(grep -o '"next_cursor":"[^"]*"' <<<"$page1")"

step "Following next_cursor"
cursor=$(sed -E 's/.*"next_cursor":"([^"]+)".*/\1/' <<<"$page1")
page2=$(curl -s "$API/v1/shipments?cursor=$cursor" -H "Authorization: Bearer $K")
echo "second page: $(grep -o '"tracking_code"' <<<"$page2" | wc -l) items, $(grep -o '"has_more":[a-z]*' <<<"$page2")"
