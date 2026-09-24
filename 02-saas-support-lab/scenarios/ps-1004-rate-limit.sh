#!/usr/bin/env bash
# PS-1004 - "Your API blocks us every night during our sync." (Litoral Bikes)
# Their nightly job fires requests back to back with no pause and no retry logic.
source "$(dirname "$0")/lib.sh"
R=$(key cus_litoral read_key)

step "What their sync does: 15 requests as fast as possible"
for i in $(seq 1 15); do
  printf 'request %2d -> %s\n' "$i" "$(curl -s -o /dev/null -w '%{http_code}' "$API/v1/shipments" -H "Authorization: Bearer $R")"
done

step "The 429 response in full"
req curl -s -i "$API/v1/shipments" -H "Authorization: Bearer $R"

step "API log: rate-limit events for this customer in the last minute"
docker compose logs api --no-log-prefix --since 1m 2>/dev/null | grep '"rate_limited"' | grep -c cus_litoral | sed 's/^/rate_limited events: /'
api_log '"rate_limited"' | tail -1

step "A client that honours Retry-After"
wait_s=$(curl -s -i "$API/v1/shipments" -H "Authorization: Bearer $R" | tr -d '\r' | sed -n 's/^retry-after: //Ip')
echo "Retry-After: ${wait_s:-0}s -> sleeping, then retrying"
sleep "${wait_s:-0}"
req curl -s -o /dev/null -w 'HTTP %{http_code}\n' "$API/v1/shipments" -H "Authorization: Bearer $R"
