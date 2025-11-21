#!/usr/bin/env bash
set -euo pipefail

auth_url="${ST_AUTH_URL:-}"
client_id="${ST_AUTH_CLIENT_ID:-}"
client_secret="${ST_AUTH_CLIENT_SECRET:-}"
username="${ST_AUTH_USERNAME:-}"
password="${ST_AUTH_PASSWORD:-}"
grant_type="${ST_AUTH_GRANT_TYPE:-client_credentials}"

if [ -z "$auth_url" ] || [ -z "$client_id" ]; then
  echo "ST_AUTH_URL and ST_AUTH_CLIENT_ID must be set" >&2
  exit 1
fi

if [ "$grant_type" = "password" ]; then
  if [ -z "$username" ] || [ -z "$password" ]; then
    echo "ST_AUTH_USERNAME and ST_AUTH_PASSWORD must be set for password grant" >&2
    exit 1
  fi
fi

data="grant_type=$grant_type&client_id=$client_id"
if [ -n "$client_secret" ]; then
  data="$data&client_secret=$client_secret"
fi
if [ "$grant_type" = "password" ]; then
  data="$data&username=$username&password=$password"
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

response=$(curl -sS -X POST "$auth_url" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data "$data")

printf '%s\n' "$response" | python3 << 'PY'
import json
import sys

data = sys.stdin.read()
try:
    obj = json.loads(data)
except json.JSONDecodeError:
    sys.stderr.write("Failed to parse auth response as JSON\n")
    sys.stderr.write(data + "\n")
    sys.exit(1)

for key in ("access_token", "id_token"):
    token = obj.get(key)
    if token:
        sys.stdout.write(token)
        sys.exit(0)

sys.stderr.write("No access_token or id_token found in auth response\n")
sys.stderr.write(data + "\n")
sys.exit(1)
PY
