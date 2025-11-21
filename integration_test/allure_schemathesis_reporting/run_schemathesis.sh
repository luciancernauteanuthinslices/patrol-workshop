#!/usr/bin/env bash
# run_schemathesis.sh — Self-contained runner for Schemathesis (JUnit+HAR reports)
# Works with token from .schemathesis_token and supports many flags from `schemathesis run --help`.
# Default: uses venv binary ./integration_test/myenv/bin/schemathesis (override with $SCHEMATHESIS_BIN).

set -euo pipefail

# ------------------ Defaults (override via env or CLI) -----------------------
SCHEMATHESIS_BIN="${SCHEMATHESIS_BIN:-./integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis}"
SCHEMA="${SCHEMA:-openapi-docs.yaml}"       # open api schema file path
BASE_URL="${ST_URL:-}"                      # can be set by -u / --url too
REPORT_DIR="${ST_DIR:-integration_test/allure_schemathesis_reporting/schemathesis-report}"
WORKERS="${ST_WORKERS:-5}"                  # -n
WEIGHT="${ST_WEIGHT:-auto}"                 # -w
PHASES="${ST_PHASES:-examples,coverage}"    # --phases
MODE="${ST_MODE:-all}"                      # --mode (positive|negative|all)
EXCLUDE_DEPRECATED="${EXCLUDE_DEPRECATED:-1}"
CHECKS="${ST_CHECKS:-}"                     # e.g. all or 'not_a_server_error,invalid_schema'
MAX_EXAMPLES="${ST_MAX_EXAMPLES:-}"         # Hypothesis max examples per operation
DEADLINE_MS="${ST_DEADLINE_MS:-}"           # Hypothesis deadline in ms
RATE_LIMIT="${ST_RATE_LIMIT:-}"             # e.g. 10/s
VALIDATE_SCHEMA="${ST_VALIDATE_SCHEMA:-0}"  # --validate-schema
ENDPOINT_FILTER="${ST_ENDPOINT:-}"          # --endpoint regex
METHOD_FILTER="${ST_METHOD:-}"              # --method GET|POST|...
TAG_FILTER="${ST_TAG:-}"                    # --tag 'smoke'
OP_ID_FILTER="${ST_OPERATION_ID:-}"         # --operation-id name
TIMEOUT_SECS="${ST_TIMEOUT_SECS:-0}"        # Abort run after N seconds (0=off)
WAIT_TOKEN_SECS="${WAIT_TOKEN_SECS:-60}"    # wait up to N seconds for token file to appear
TOKEN_FILE="${TOKEN_FILE:-.schemathesis_token}"
AUTH_HEADER_ENV="${AUTH_HEADER:-}"          # If set, used as header directly
EXTRA_HEADERS="${ST_EXTRA_HEADERS:-}"       # comma-separated: 'X-Env:dev,X-Feature:foo'
LOG_STDOUT="${ST_LOG_STDOUT:-0}"            # 1=also print to console with tee
DEBUG="${DEBUG:-0}"
AUTO_VENV="${AUTO_VENV:-0}"                 # 1=create venv and install schemathesis if missing
HYPOTHESIS_DATABASE_FILE="${HYPOTHESIS_DATABASE_FILE:-integration_test/.hypothesis/examples.db}"
mkdir -p "$(dirname "$HYPOTHESIS_DATABASE_FILE")"
export HYPOTHESIS_DATABASE_FILE

usage() {
  cat <<USAGE
Usage:
  $0 -u <base-url> [-s <schema>] [options]

Required:
  -u, --url URL            Base URL of the API under test

Common:
  -s, --schema PATH        OpenAPI schema path/URL (default: $SCHEMA)
  -n, --workers N          Concurrency (default: $WORKERS)
  -w, --weight W           Load distribution: auto|positive|negative (default: $WEIGHT)
      --phases LIST        examples,coverage (default: $PHASES)
      --mode M             positive|negative|all (default: $MODE)
      --exclude-deprecated Skip deprecated operations (default: $EXCLUDE_DEPRECATED)
  -H "Header: Value"       Repeatable; extra header(s)
      --header-file PATH   File with additional headers (one per line)
      --rate-limit R       RPS, e.g. 10/s
      --checks LIST        e.g. all OR not_a_server_error,invalid_schema
      --max-examples N     Hypothesis max examples per operation
      --deadline MS        Hypothesis deadline per test
      --validate-schema    Validate schema before run
      --endpoint REGEX     Filter operations by endpoint (regex)
      --method NAME        Filter by method: GET|POST|...
      --tag TAG            Filter by OpenAPI tag
      --operation-id ID    Filter by operationId
      --timeout SEC        Kill run after SEC (host timeout, not API)
      --wait-token SEC     Wait up to SEC for .schemathesis_token (default: $WAIT_TOKEN_SECS)
      --report-dir DIR     (default: $REPORT_DIR)

Token:
  If AUTH_HEADER is set, it will be used.
  Otherwise we read a Bearer from $TOKEN_FILE and pass header:
    Authorization: Bearer <token>

Env vars:
  SCHEMATHESIS_BIN, ST_URL, ST_DIR, ST_PHASES, ST_MODE, EXCLUDE_DEPRECATED, ST_CHECKS, ST_MAX_EXAMPLES,
  ST_DEADLINE_MS, ST_RATE_LIMIT, ST_VALIDATE_SCHEMA, ST_ENDPOINT, ST_METHOD, ST_TAG, ST_OPERATION_ID,
  ST_TIMEOUT_SECS, WAIT_TOKEN_SECS, TOKEN_FILE, AUTH_HEADER, ST_EXTRA_HEADERS, ST_LOG_STDOUT, DEBUG, AUTO_VENV

Examples:
  $0 -u https://api.dev.example.com -s openapi-docs.yaml
  $0 -u $ST_URL --checks all --max-examples 50 --rate-limit 20/s -H "X-Env: dev"
  AUTH_HEADER="Authorization: Bearer $(cat .schemathesis_token)" $0 -u $ST_URL
USAGE
}

# ------------------ Parse CLI ------------------------------------------------
HEADERS=()
HEADER_FILE=""
while (( "$#" )); do
  case "$1" in
    -u|--url) BASE_URL="$2"; shift 2;;
    -s|--schema) SCHEMA="$2"; shift 2;;
    -n|--workers) WORKERS="$2"; shift 2;;
    -w|--weight) WEIGHT="$2"; shift 2;;
    --phases) PHASES="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --exclude-deprecated) EXCLUDE_DEPRECATED=1; shift 1;;
    -H) HEADERS+=("$2"); shift 2;;
    --header-file) HEADER_FILE="$2"; shift 2;;
    --rate-limit) RATE_LIMIT="$2"; shift 2;;
    --checks) CHECKS="$2"; shift 2;;
    --max-examples) MAX_EXAMPLES="$2"; shift 2;;
    --deadline) DEADLINE_MS="$2"; shift 2;;
    --validate-schema) VALIDATE_SCHEMA=1; shift 1;;
    --endpoint) ENDPOINT_FILTER="$2"; shift 2;;
    --method) METHOD_FILTER="$2"; shift 2;;
    --tag) TAG_FILTER="$2"; shift 2;;
    --operation-id) OP_ID_FILTER="$2"; shift 2;;
    --timeout) TIMEOUT_SECS="$2"; shift 2;;
    --wait-token) WAIT_TOKEN_SECS="$2"; shift 2;;
    --report-dir) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

[ -n "$BASE_URL" ] || { echo "ERROR: Missing -u/--url"; usage; exit 2; }

# ------------------ Ensure binary -------------------------------------------
if [ ! -x "$SCHEMATHESIS_BIN" ]; then
  if [ "$AUTO_VENV" = "1" ]; then
    echo ">> Creating venv ./integration_test/allure_schemathesis_reporting/myenv and installing schemathesis..."
    python3 -m venv integration_test/allure_schemathesis_reporting/myenv
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install --upgrade pip
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install schemathesis
    SCHEMATHESIS_BIN="./integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis"
  else
    echo "ERROR: Schemathesis binary not executable at $SCHEMATHESIS_BIN"
    echo "Hint: set SCHEMATHESIS_BIN or set AUTO_VENV=1"
    exit 3
  fi
fi

mkdir -p "$REPORT_DIR"

# ------------------ Build Authorization header -------------------------------
if [ -n "$AUTH_HEADER_ENV" ]; then
  HEADERS+=("$AUTH_HEADER_ENV")
else
  # Wait for token file if needed
  if [ ! -s "$TOKEN_FILE" ] && [ "$WAIT_TOKEN_SECS" -gt 0 ]; then
    echo ">> Waiting for token file: $TOKEN_FILE (up to ${WAIT_TOKEN_SECS}s)..."
    for _ in $(seq 1 "$WAIT_TOKEN_SECS"); do
      [ -s "$TOKEN_FILE" ] && break
      sleep 1
    done
  fi
  if [ -s "$TOKEN_FILE" ]; then
    TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
    HEADERS+=("Authorization: Bearer $TOKEN")
  else
    echo "WARN: No $TOKEN_FILE and $AUTH_HEADER not set; running WITHOUT Authorization header."
  fi
fi

# Include headers from file if provided
if [ -n "$HEADER_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    HEADERS+=("$line")
  done < "$HEADER_FILE"
fi

# Include extra headers from env (comma-separated)
if [ -n "$EXTRA_HEADERS" ]; then
  IFS=',' read -ra EH <<< "$EXTRA_HEADERS"
  for h in "${EH[@]}"; do HEADERS+=("$h"); done
fi

# ------------------ Compose command ------------------------------------------
CMD=( "$SCHEMATHESIS_BIN" run "$SCHEMA" -u "$BASE_URL"
      --report=junit,har --report-dir "$REPORT_DIR"
      -n "$WORKERS" -w "$WEIGHT"
      --phases "$PHASES" --mode "$MODE"
    )

[ "$EXCLUDE_DEPRECATED" = "1" ] && CMD+=( --exclude-deprecated )
[ -n "$CHECKS" ]        && CMD+=( --checks "$CHECKS" )
[ -n "$MAX_EXAMPLES" ]  && CMD+=( --max-examples "$MAX_EXAMPLES" )
[ -n "$DEADLINE_MS" ]   && CMD+=( --deadline "$DEADLINE_MS" )
[ -n "$RATE_LIMIT" ]    && CMD+=( --rate-limit "$RATE_LIMIT" )
[ "$VALIDATE_SCHEMA" = "1" ] && CMD+=( --validate-schema )
[ -n "$ENDPOINT_FILTER" ] && CMD+=( --endpoint "$ENDPOINT_FILTER" )
[ -n "$METHOD_FILTER" ]   && CMD+=( --method "$METHOD_FILTER" )
[ -n "$TAG_FILTER" ]      && CMD+=( --tag "$TAG_FILTER" )
[ -n "$OP_ID_FILTER" ]    && CMD+=( --operation-id "$OP_ID_FILTER" )

# Headers
for h in "${HEADERS[@]:-}"; do
  CMD+=( -H "$h" )
done

# Debug print
if [ "$DEBUG" = "1" ]; then
  echo ">> CMD: ${CMD[*]}"
fi

# ------------------ Execute with optional host timeout -----------------------
OUT="$REPORT_DIR/output.txt"
if [ "$TIMEOUT_SECS" -gt 0 ]; then
  if command -v timeout >/dev/null 2>&1; then
    echo ">> Running with timeout ${TIMEOUT_SECS}s..."
    if [ "$LOG_STDOUT" = "1" ]; then
      timeout "$TIMEOUT_SECS" "${CMD[@]}" | tee "$OUT"
    else
      timeout "$TIMEOUT_SECS" "${CMD[@]}" >"$OUT" 2>&1
    fi
  else
    echo "WARN: 'timeout' not available; running without host timeout"
    if [ "$LOG_STDOUT" = "1" ]; then
      "${CMD[@]}" | tee "$OUT"
    else
      "${CMD[@]}" >"$OUT" 2>&1
    fi
  fi
else
  if [ "$LOG_STDOUT" = "1" ]; then
    "${CMD[@]}" | tee "$OUT"
  else
    "${CMD[@]}" >"$OUT" 2>&1
  fi
fi

echo ">> Schemathesis finished. Reports in: $REPORT_DIR"
