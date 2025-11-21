#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Inputs / defaults -------------------------------------------------------
SCHEMATHESIS_BIN="${SCHEMATHESIS_BIN:-./integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis}"
ST_URL="${ST_URL:-https://petstore3.swagger.io/api/v3}"
ST_SCHEMA="${ST_SCHEMA:-petStore_openapi.json}"
OUT_ROOT="${OUT_ROOT:-build/schemathesis-allure}"
RUN_ST_DIR="${RUN_ST_DIR:-$OUT_ROOT/run}"
RESULTS_DIR="${RESULTS_DIR:-$OUT_ROOT/allure-results}"
REPORT_DIR="${REPORT_DIR:-build/allure-report-schemathesis}"

# ---- Schemathesis defaults ---------------------------------------------------
# Valid phases: examples, coverage, fuzzing, stateful
ST_PHASES="${ST_PHASES:-examples,coverage,stateful}"
ST_MODE="${ST_MODE:-all}"
ST_WORKERS="${ST_WORKERS:-5}"
ST_WEIGHT="${ST_WEIGHT:-auto}"

GET_TOKEN_MODE="${GET_TOKEN_MODE:-export_token}"  # export_token | direct_api
WAIT_TOKEN_SECS="${WAIT_TOKEN_SECS:-60}"
PKG="${PKG:-com.example.patrol_challenge}"
BUNDLE_ID="${BUNDLE_ID:-pl.leancode.patrol.challenge.dev}"
AUTH_SCRIPT="${AUTH_SCRIPT:-integration_test/allure_schemathesis_reporting/sct_auth/get_schemathesis_token.sh}"
IOS_PULL="${IOS_PULL:-integration_test/allure_schemathesis_reporting/sct_auth/ios_pull_token.sh}"

rm -rf "$RUN_ST_DIR" "$RESULTS_DIR"
mkdir -p "$RUN_ST_DIR" "$RESULTS_DIR"

[ -n "$ST_URL" ] || { echo "ERROR: ST_URL must be set" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 2; }; }

need_cmd python3
need_cmd allure
 
AUTO_VENV="${AUTO_VENV:-0}"  # 1=create venv and install schemathesis if missing

if [ ! -x "$SCHEMATHESIS_BIN" ]; then
  if [ "$AUTO_VENV" = "1" ]; then
    echo ">> Creating venv ./integration_test/allure_schemathesis_reporting/myenv and installing schemathesis..."
    rm -rf integration_test/allure_schemathesis_reporting/myenv
    python3 -m venv integration_test/allure_schemathesis_reporting/myenv
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install --upgrade pip
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install schemathesis
    SCHEMATHESIS_BIN="./integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis"
  else
    echo "ERROR: Schemathesis binary not executable at $SCHEMATHESIS_BIN" >&2
    echo "Hint: set SCHEMATHESIS_BIN or set AUTO_VENV=1" >&2
    exit 2
  fi
fi

if ! "$SCHEMATHESIS_BIN" --help >/dev/null 2>&1; then
  if [ "$AUTO_VENV" = "1" ]; then
    echo ">> Detected broken Schemathesis binary at $SCHEMATHESIS_BIN; recreating venv..."
    rm -rf integration_test/allure_schemathesis_reporting/myenv
    python3 -m venv integration_test/allure_schemathesis_reporting/myenv
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install --upgrade pip
    ./integration_test/allure_schemathesis_reporting/myenv/bin/pip install schemathesis
    SCHEMATHESIS_BIN="./integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis"
  else
    echo "ERROR: Schemathesis binary at $SCHEMATHESIS_BIN is not runnable" >&2
    echo "Hint: recreate your venv or set SCHEMATHESIS_BIN to a valid schemathesis executable." >&2
    exit 2
  fi
fi

# ---- Token resolution --------------------------------------------------------
get_token_export_mode() {
  if [ -s ./.schemathesis_token ]; then
    return 0
  fi

  echo ">> Waiting up to ${WAIT_TOKEN_SECS}s for .schemathesis_token from device/simulator..."
  SECS=0
  while [ $SECS -lt "$WAIT_TOKEN_SECS" ]; do
    if [ -s ./.schemathesis_token ]; then
      return 0
    fi

    if command -v adb >/dev/null 2>&1; then
      adb exec-out run-as "$PKG" cat "/data/data/$PKG/app_flutter/.schemathesis_token" > ./.schemathesis_token 2>/dev/null || true
    elif command -v xcrun >/dev/null 2>&1; then
      BUNDLE_ID="$BUNDLE_ID" bash "$IOS_PULL" >/dev/null 2>&1 || true
    fi

    if [ -s ./.schemathesis_token ]; then
      return 0
    fi

    sleep 2
    SECS=$((SECS+2))
  done

  echo "ERROR: Could not obtain token via export_token mode" >&2
  exit 3
}

get_token_direct_api() {
  need_cmd curl
  if [ ! -x "$AUTH_SCRIPT" ]; then
    echo "ERROR: Auth script not executable: $AUTH_SCRIPT" >&2
    exit 4
  fi
  echo ">> Obtaining Schemathesis token via direct_api script..."
  TOKEN="$($AUTH_SCRIPT)" || {
    echo "ERROR: Auth script failed" >&2
    exit 5
  }
  printf '%s' "$TOKEN" > ./.schemathesis_token
}

case "$GET_TOKEN_MODE" in
  export_token) get_token_export_mode ;;
  direct_api)   get_token_direct_api  ;;
  *) echo "ERROR: GET_TOKEN_MODE must be export_token or direct_api" >&2; exit 1;;
esac

AUTH_HEADER="Authorization: Bearer $(tr -d '\r\n' < ./.schemathesis_token)"

# ---- Run Schemathesis --------------------------------------------------------
echo ">> Running Schemathesis..."
set +e
"$SCHEMATHESIS_BIN" run "$ST_SCHEMA" \
  -u "$ST_URL" \
  -H "$AUTH_HEADER" \
  --exclude-deprecated \
  --phases "$ST_PHASES" \
  --mode "$ST_MODE" \
  -n "$ST_WORKERS" -w "$ST_WEIGHT" \
  --report=junit,har --report-dir "$RUN_ST_DIR" \
  > "$RUN_ST_DIR/output.txt" 2>&1
RC=$?
set -e

JUNIT_FILE=$(ls -1t "$RUN_ST_DIR"/junit-*.xml 2>/dev/null | head -n1 || true)
HAR_FILE=$(ls -1t "$RUN_ST_DIR"/har-*.json 2>/dev/null | head -n1 || true)

if [ -z "$JUNIT_FILE" ] || [ ! -f "$JUNIT_FILE" ]; then
  echo "ERROR: No JUnit report produced by Schemathesis in $RUN_ST_DIR" >&2
  exit 6
fi

# ---- Aggregate JUnit -> Allure (1 test per endpoint/operation) --------------
python3 "$SCRIPT_DIR/st_aggregate_to_allure.py" \
  --junit "$JUNIT_FILE" \
  ${HAR_FILE:+--har "$HAR_FILE"} \
  --base-url "$ST_URL" \
  --schema "$ST_SCHEMA" \
  --out "$RESULTS_DIR"

# ---- Generate the separate Allure report ------------------------------------
echo ">> Generating Schemathesis Allure report -> $REPORT_DIR"
allure generate "$RESULTS_DIR" -o "$REPORT_DIR" --clean

echo ">> Done. Schemathesis exit code: $RC"
exit "$RC"
