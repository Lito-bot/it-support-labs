#!/usr/bin/env bash
# Shared helpers for the scenario scripts. Keys come from shared/lab-keys.json
# (generated at first boot, git-ignored) and are redacted in everything printed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

API=http://127.0.0.1:8080
SHOP=http://127.0.0.1:8090
KEYS=shared/lab-keys.json

# key <customer_id> <read_key|write_key|webhook_secret>
key() { sed -n "/\"$1\"/,/}/p" "$KEYS" | grep "\"$2\"" | sed -E 's/.*: "([^"]+)".*/\1/'; }

redact() { sed -E 's/(pcl_live_)[0-9a-f]{24}/\1<redacted>/g; s/(whsec_)[0-9a-f]+/\1<redacted>/g'; }

step() { printf '\n### %s\n' "$*"; }

# Print a command the way you'd type it: args with spaces or quotes get single-quoted.
fmt_cmd() {
  local out="" a
  for a in "$@"; do
    if [[ "$a" =~ [[:space:]\"\'\{\}\&\?\;] ]]; then out+=" '${a//\'/\'\\\'\'}'"; else out+=" $a"; fi
  done
  printf '\n$%s\n' "$out" | redact
}

# req <command...>: print the command (secrets redacted), run it, print the output,
# and keep the raw output in $OUT for later steps
req() {
  fmt_cmd "$@"
  OUT=$("$@" 2>&1 | tr -d '\r')
  grep -viE '^(date|server|content-length):' <<<"$OUT" | redact
}

# request_id_of <curl -i output>
request_id_of() { tr -d '\r' <<<"$1" | sed -n 's/^x-request-id: //Ip'; }

# api_log <pattern>: the API's JSON log lines matching a request/event id
api_log() { [[ -n "$1" ]] || { echo "(no id to search for)"; return; }; docker compose logs api --no-log-prefix 2>/dev/null | grep -F "$1" | redact; }
shop_log() { [[ -n "$1" ]] || { echo "(no id to search for)"; return; }; docker compose logs customer --no-log-prefix 2>/dev/null | grep -F "$1" | redact; }
