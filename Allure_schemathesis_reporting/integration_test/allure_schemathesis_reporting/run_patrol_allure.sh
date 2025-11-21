#!/usr/bin/env bash
# run one-time before in console: chmod +x integration_test/allure_schemathesis_reporting/run_patrol_allure.sh

set -euo pipefail

# --- INPUTS / DEFAULTS -------------------------------------------------------
TARGET="${1:-${TARGET:-integration_test}}"   # allow arg, $TARGET, or default directory
RUN_DIR="build/reports/allure-results/$(date +%Y%m%d-%H%M%S)-$$"
REPORT_DIR="build/allure-report"
PLATFORM="${PLATFORM:-auto}"   # android|ios|auto
ALLURE_XCRESULT_BIN="${ALLURE_XCRESULT_BIN:-}"
ALLURE_XCRESULT_REPO="${ALLURE_XCRESULT_REPO:-}"
ENV_FILE="integration_test/allure_schemathesis_reporting/patrol_env.sh"
# Preserve any user-provided values before sourcing env file
ORIG_TAGS="${TAGS:-}"
ORIG_EXCLUDE_TAGS="${EXCLUDE_TAGS:-}"

# --- SCHEMATHESIS INTEGRATION (toggles & defaults) ---------------------------
RUN_ST="${RUN_ST:-1}"  # 1=start Schemathesis wrapper in background
SCHEMATHESIS_WRAPPER="${SCHEMATHESIS_WRAPPER:-./integration_test/allure_schemathesis_reporting/run_schemathesis.sh}"
ST_SCHEMA="${ST_SCHEMA:-openapi-docs.yaml}"
ST_URL="${ST_URL:-}"                         # e.g. https://api.dev.example.com
ST_DIR="${ST_DIR:-integration_test/allure_schemathesis_reporting/schemathesis-report}"
ST_AUTH_SCRIPT="${ST_AUTH_SCRIPT:-integration_test/allure_schemathesis_reporting/sct_auth/get_schemathesis_token.sh}"
GET_TOKEN_MODE="${GET_TOKEN_MODE:-${GET_TOKEN:-export_token}}"
ST_WAIT_TOKEN_SECS="${ST_WAIT_TOKEN_SECS:-120}"  # wrapper waits up to N seconds for .schemathesis_token
ST_FINISH_TIMEOUT_SECS="${ST_FINISH_TIMEOUT_SECS:-0}"  # 0 = don't wait for finish before import
ST_PULL_TOKEN_TIMEOUT_SECS="${ST_PULL_TOKEN_TIMEOUT_SECS:-300}"  # how long this script tries to pull token to host
PKG="${PKG:-com.thinslices.solarisdemo}"          # Android package name
BUNDLE_ID="${BUNDLE_ID:-com.thinslices.solarisdemo}"  # iOS bundle identifier
SERVE_REPORT="${SERVE_REPORT:-1}"  # 1=also run `allure serve`, 0=only generate static HTML

# --- SANITY CHECKS (common) --------------------------------------------------
if ! command -v patrol >/dev/null; then
  echo "ERROR: Patrol CLI not found in PATH."; exit 4
fi
if ! command -v allure >/dev/null; then
  echo "ERROR: Allure CLI not found in PATH."; exit 3
fi
# Optional: load environment exports (does not override user-provided values)
if [ -f "$ENV_FILE" ]; then . "$ENV_FILE"; fi

# Re-apply precedence: command-line/env overrides file defaults
TAGS="${ORIG_TAGS:-${TAGS:-}}"
EXCLUDE_TAGS="${ORIG_EXCLUDE_TAGS:-${EXCLUDE_TAGS:-}}"

if [ ! -f "$TARGET" ] && [ ! -d "$TARGET" ]; then
  echo "Usage: $0 integration_test/your_test.dart | integration_test/"
  echo "Tip: pass a file, a directory, or set \$TARGET. Current: '$TARGET' not found."
  exit 1
fi

# --- DETECT PLATFORM ---------------------------------------------------------
detect_platform() {
  if [ "$PLATFORM" = "android" ]; then echo android; return; fi
  if [ "$PLATFORM" = "ios" ]; then echo ios; return; fi
  if command -v adb >/dev/null 2>&1; then
    # Consider Android available if there is at least one attached device in "device" state
    if adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{exit 0} END{exit 1}'; then
      echo android
      return
    fi
  fi
  if command -v xcrun >/dev/null 2>&1; then echo ios; return; fi
  echo android
}

PLAT=$(detect_platform)
if command -v adb >/dev/null 2>&1; then
  if [ -z "${ADB_TARGET:-}" ]; then
    ADB_TARGET=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
  fi
fi

# --- HELPERS -----------------------------------------------------------------
convert_xcresult() {
  local input="$1"; shift
  local output="$1"; shift
  if [ -n "$ALLURE_XCRESULT_BIN" ] && [ -x "$ALLURE_XCRESULT_BIN" ]; then
    echo ">> Using converter: $ALLURE_XCRESULT_BIN"
    "$ALLURE_XCRESULT_BIN" --input "$input" --output "$output"
    return
  fi
  if command -v allure-xcresult >/dev/null 2>&1; then
    echo ">> Using converter binary in PATH: allure-xcresult"
    allure-xcresult --input "$input" --output "$output"
    return
  fi
  if command -v AllureXCResult >/dev/null 2>&1; then
    echo ">> Using converter binary in PATH: AllureXCResult"
    AllureXCResult --input "$input" --output "$output"
    return
  fi
  if [ -n "$ALLURE_XCRESULT_REPO" ] && [ -d "$ALLURE_XCRESULT_REPO" ]; then
    echo ">> Using swift run from repo: $ALLURE_XCRESULT_REPO"
    (cd "$ALLURE_XCRESULT_REPO" && swift run -c release AllureXCResult --input "$input" --output "$output")
    return
  fi
  echo "ERROR: No allure-xcresult converter found. Set ALLURE_XCRESULT_BIN to the built binary path or ALLURE_XCRESULT_REPO to the cloned repo." >&2
  exit 5
}

init_schemathesis_auth() {
  if [ "${RUN_ST}" != "1" ]; then return; fi
  if [ "$GET_TOKEN_MODE" != "direct_api" ]; then return; fi
  if [ -n "${AUTH_HEADER:-}" ]; then return; fi
  if [ ! -x "${ST_AUTH_SCRIPT}" ]; then return; fi
  if [ -z "${ST_AUTH_URL:-}" ] || [ -z "${ST_AUTH_CLIENT_ID:-}" ]; then return; fi
  echo ">> Obtaining Schemathesis token via auth script..."
  if ! TOKEN="$(${ST_AUTH_SCRIPT})"; then
    echo "WARN: Auth script failed; falling back to device token export if available."
    return
  fi
  AUTH_HEADER="Authorization: Bearer ${TOKEN}"
  export AUTH_HEADER
  printf '%s' "${TOKEN}" > ./.schemathesis_token || true
}

# --- SCHEMATHESIS HELPERS ----------------------------------------------------
pull_token_background() {
  # Attempt to copy token from device/simulator to host ./.schemathesis_token
  # Retries up to ST_PULL_TOKEN_TIMEOUT_SECS but returns immediately if already present
  if [ "$GET_TOKEN_MODE" != "export_token" ]; then return; fi
  # Always refresh the host token file for each run
  rm -f ./.schemathesis_token 2>/dev/null || true
  echo ">> Starting token puller (auto-detect platform) ..."
  (
    SECS=0
    while [ $SECS -lt "$ST_PULL_TOKEN_TIMEOUT_SECS" ]; do
      if [ -s ./.schemathesis_token ]; then exit 0; fi
      if command -v adb >/dev/null 2>&1; then
        if [ -z "${ADB_TARGET:-}" ]; then
          ADB_TARGET=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')
        fi
        if [ -n "${ADB_TARGET:-}" ]; then
          adb ${ADB_TARGET:+-s "$ADB_TARGET"} exec-out run-as "$PKG" cat "/data/data/$PKG/app_flutter/.schemathesis_token" > ./.schemathesis_token 2>/dev/null || true
        fi
      fi
      if [ ! -s ./.schemathesis_token ] && command -v xcrun >/dev/null 2>&1; then
        BUNDLE_ID="$BUNDLE_ID" bash integration_test/allure_schemathesis_reporting/sct_auth/ios_pull_token.sh >/dev/null 2>&1 || true
      fi
      if [ -s ./.schemathesis_token ]; then exit 0; fi
      sleep 2; SECS=$((SECS+2))
    done
    exit 0
  ) &
}

start_schemathesis() {
  if [ "$RUN_ST" != "1" ]; then return; fi
  if [ -z "$ST_URL" ]; then echo ">> ST_URL not set; skip Schemathesis."; return; fi
  if [ ! -x "$SCHEMATHESIS_WRAPPER" ]; then echo ">> Schemathesis wrapper not executable at $SCHEMATHESIS_WRAPPER (skip)."; return; fi
  mkdir -p "$ST_DIR"
  echo ">> Starting Schemathesis in background via wrapper..."
  WAIT_TOKEN_SECS="$ST_WAIT_TOKEN_SECS" ST_DIR="$ST_DIR" \
    "$SCHEMATHESIS_WRAPPER" -u "$ST_URL" -s "$ST_SCHEMA" &
  ST_PID=$!
}

import_schemathesis_into_allure() {
  local junit_latest
  local har_latest
  junit_latest=$(ls -1t "$ST_DIR"/junit-*.xml 2>/dev/null | head -n1 || true)
  har_latest=$(ls -1t "$ST_DIR"/har-*.json 2>/dev/null | head -n1 || true)
  local out_txt="$ST_DIR/output.txt"

  if [ -z "$junit_latest" ] || [ ! -f "$junit_latest" ]; then
    echo ">> Schemathesis JUnit not found in $ST_DIR (skip import)"
    return
  fi

  echo ">> Importing Schemathesis artifacts into Allure..."
  local safe_har=""
  if [ -n "$har_latest" ] && [ -f "$har_latest" ]; then
    safe_har="$RUN_DIR/schemathesis-har-redacted.har"
    sed -E 's/(Authorization"\:\s*"Bearer\s*)[^"]+/\1***REDACTED***/g' "$har_latest" \
      | sed -E 's/(Authorization\:\s*Bearer\s*)[A-Za-z0-9._-]+/\1***REDACTED***/g' > "$safe_har"
  fi

  local sum_txt="$RUN_DIR/schemathesis-summary.txt"
  local sum_html="$RUN_DIR/schemathesis-summary.html"
  local sum_json="$RUN_DIR/schemathesis-summary.json"

  python3 - <<PY "$junit_latest" "$sum_txt" "$sum_html" "$sum_json"
import sys, xml.etree.ElementTree as ET, html, json
junit, out_txt, out_html, out_json = sys.argv[1:5]
t = ET.parse(junit).getroot()
ts = t if t.tag.endswith("testsuite") else next((c for c in t if c.tag.endswith("testsuite")), t)
tests  = int(ts.attrib.get("tests", 0))
fail   = int(ts.attrib.get("failures", ts.attrib.get("failuresCount", 0)))
err    = int(ts.attrib.get("errors", 0))
skip   = int(ts.attrib.get("skipped", ts.attrib.get("skip", 0)))
name   = ts.attrib.get("name", "Schemathesis")
status = "passed" if (fail==0 and err==0) else "failed"
open(out_txt,"w").write(f"Suite: {name}\nTests: {tests}\nFailures: {fail}\nErrors: {err}\nSkipped: {skip}\nStatus: {status}\n")
open(out_html,"w").write("""<!doctype html>
<meta charset=\"utf-8\"><title>Schemathesis Summary</title>
<style>body{font:14px/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial} .k{font-weight:600}</style>
<h2>Schemathesis Summary</h2>
<p><span class=\"k\">Suite:</span> %s</p>
<p><span class=\"k\">Tests:</span> %d &nbsp; <span class=\"k\">Failures:</span> %d &nbsp; <span class=\"k\">Errors:</span> %d &nbsp; <span class=\"k\">Skipped:</span> %d</p>
<p><span class=\"k\">Status:</span> <b>%s</b></p>""" % (html.escape(name), tests, fail, err, skip, status.upper()))
with open(out_json,"w") as f:
  json.dump({"suite":name,"tests":tests,"failures":fail,"errors":err,"skipped":skip,"status":status}, f, indent=2)
PY

  local st_status
  st_status=$(python3 - <<PY "$junit_latest"
import sys, xml.etree.ElementTree as ET
t=ET.parse(sys.argv[1]).getroot()
ts = t if t.tag.endswith("testsuite") else next((c for c in t if c.tag.endswith("testsuite")), t)
fail=int(ts.attrib.get("failures", ts.attrib.get("failuresCount", 0)))
err=int(ts.attrib.get("errors",0))
print("passed" if (fail==0 and err==0) else "failed")
PY
)

  local uuid
  uuid=$( (uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) 2>/dev/null || date +%s%N )
  [ -z "$uuid" ] && uuid=$(date +%s%N)

  # Copy JUnit XML as attachment-only (non-.xml extension) so Allure does not import 29 separate tests
  local junit_copy="$RUN_DIR/schemathesis-results-$uuid.xml.txt"
  cp -f "$junit_latest" "$junit_copy"
  cp -f "$sum_txt" "$RUN_DIR/schemathesis-summary-$uuid.txt"
  cp -f "$sum_html" "$RUN_DIR/schemathesis-summary-$uuid.html"
  cp -f "$sum_json" "$RUN_DIR/schemathesis-summary-$uuid.json"
  if [ -n "$safe_har" ] && [ -f "$safe_har" ]; then
    cp -f "$safe_har" "$RUN_DIR/schemathesis-har-$uuid.har"
  fi
  if [ -f "$out_txt" ]; then
    cp -f "$out_txt" "$RUN_DIR/schemathesis-output-$uuid.txt"
  fi

  local now_ms=$(( $(date +%s%N)/1000000 ))
  cat > "$RUN_DIR/$uuid-result.json" <<JSON
{
  "uuid": "$uuid",
  "name": "Schemathesis contract",
  "fullName": "Schemathesis contract",
  "status": "$st_status",
  "stage": "finished",
  "start": $now_ms,
  "stop": $now_ms,
  "labels": [
    {"name":"suite","value":"Schemathesis"},
    {"name":"feature","value":"API Contract"},
    {"name":"framework","value":"schemathesis"},
    {"name":"severity","value":"normal"}
  ],
  "attachments": [
    {"name":"JUnit XML","type":"application/xml","source":"$(basename "$junit_copy")"},
    {"name":"Summary (HTML)","type":"text/html","source":"schemathesis-summary-$uuid.html"},
    {"name":"Summary (TXT)","type":"text/plain","source":"schemathesis-summary-$uuid.txt"},
    {"name":"Summary (JSON)","type":"application/json","source":"schemathesis-summary-$uuid.json"}
  ]
}
JSON

  if [ -f "$RUN_DIR/schemathesis-har-$uuid.har" ]; then
    python3 - <<'PY' "$RUN_DIR/$uuid-result.json"
import sys, json
p=sys.argv[1]
j=json.load(open(p))
j["attachments"].append({"name":"HTTP Archive (HAR)","type":"application/json","source":[s for s in j["attachments"] if s["name"]=="Summary (JSON)"][0]["source"].replace("schemathesis-summary","schemathesis-har").replace(".json",".har")})
open(p,"w").write(json.dumps(j,indent=2))
PY
  fi
  if [ -f "$RUN_DIR/schemathesis-output-$uuid.txt" ]; then
    python3 - <<'PY' "$RUN_DIR/$uuid-result.json"
import sys, json
p=sys.argv[1]
j=json.load(open(p))
j["attachments"].append({"name":"Console Output","type":"text/plain","source":[s for s in j["attachments"] if s["name"]=="Summary (JSON)"][0]["source"].replace("schemathesis-summary","schemathesis-output").replace(".json",".txt")})
open(p,"w").write(json.dumps(j,indent=2))
PY
  fi

  # Mark pipeline failure if Schemathesis failed
  if [ "$st_status" = "failed" ]; then ANY_FAIL=1; fi

  # Remove any other Schemathesis-origin tests so only the aggregate "Schemathesis contract" remains
  for f in "$RUN_DIR"/*-result.json; do
    [ "$f" = "$RUN_DIR/$uuid-result.json" ] && continue
    if grep -q '"framework":"schemathesis"' "$f" 2>/dev/null; then
      rm -f "$f" || true
    fi
  done
}

# --- RUN TESTS ---------------------------------------------------------------
PATROL_ARGS=()
if [ -n "$TAGS" ]; then PATROL_ARGS+=(--tags "$TAGS"); fi
if [ -n "$EXCLUDE_TAGS" ]; then PATROL_ARGS+=(--exclude-tags "$EXCLUDE_TAGS"); fi

if [ -n "${EXPORT_TOKEN:-}" ] && [ "${EXPORT_TOKEN}" != "0" ] && [ "${EXPORT_TOKEN}" != "false" ]; then
  PATROL_ARGS+=(--dart-define=EXPORT_TOKEN=true)
fi

ANY_FAIL=0
MULTI=0
if [ "$#" -gt 1 ]; then MULTI=1; fi

# Start token puller and Schemathesis (optional) before running Patrol
init_schemathesis_auth
pull_token_background
start_schemathesis

if [ "$MULTI" -eq 1 ]; then
  # Run each provided test file sequentially, aggregate results, continue on failures
  mkdir -p "$(dirname "$RUN_DIR")"
  for TEST_FILE in "$@"; do
    if [ ! -f "$TEST_FILE" ]; then
      echo ">> Skipping non-file argument: $TEST_FILE"
      continue
    fi
    echo ">> Running Patrol on: $TEST_FILE (platform: $PLAT)"
    set +e
    patrol test --target "$TEST_FILE" ${PATROL_ARGS[@]+"${PATROL_ARGS[@]}"}
    RC=$?
    set -e

    if [ "$PLAT" = "android" ]; then
      mkdir -p "$RUN_DIR"
      if ! adb ${ADB_TARGET:+-s "$ADB_TARGET"} get-state >/dev/null 2>&1; then
        echo "ERROR: No Android device/emulator detected (adb)."; exit 2
      fi
      echo ">> Pulling Allure results from Android device..."
      adb ${ADB_TARGET:+-s "$ADB_TARGET"} exec-out sh -c 'cd /sdcard/googletest/test_outputfiles && tar cf - allure-results' \
      | tar xvf - -C "$RUN_DIR" --strip-components=1
    else
      echo ">> Locating latest .xcresult..."
      LATEST_XCRESULT=$(find build -maxdepth 3 -name "*.xcresult" -type d -print0 2>/dev/null | xargs -0 ls -1td 2>/dev/null | head -n1)
      if [ -z "${LATEST_XCRESULT:-}" ] || [ ! -d "$LATEST_XCRESULT" ]; then
        echo "ERROR: Could not find .xcresult bundle under ./build. Set $XCRESULT_PATH explicitly."; exit 6
      fi
      # Populate iOS device info for Allure environment if not provided
      if [ -z "${DEVICE_NAME:-}" ] || [ -z "${API_LEVEL:-}" ]; then
        if command -v python3 >/dev/null 2>&1; then
          IOS_INFO="$(python3 - <<'PY'
import json, subprocess, re
data=json.loads(subprocess.check_output(["xcrun","simctl","list","devices","-j"]))
boot=None; rt=""
for runtime, devices in data.get("devices",{}).items():
    for d in devices:
        if d.get("state")=="Booted":
            boot=d; rt=runtime; break
    if boot: break
name=boot.get("name","") if boot else ""
ver=""
m=re.search(r"iOS-(\\d+)-(\\d+)", rt)
if m: ver=f"{m.group(1)}.{m.group(2)}"
print(name)
print(ver)
PY
)"
          IOS_NAME="$(printf "%s" "$IOS_INFO" | sed -n '1p')"
          IOS_VER="$(printf "%s" "$IOS_INFO" | sed -n '2p')"
          DEVICE_NAME=${DEVICE_NAME:-"${IOS_NAME:-iOS Simulator}"}
          API_LEVEL=${API_LEVEL:-"${IOS_VER:-}"}
        else
          BOOTED_LINE=$(xcrun simctl list devices | grep -m1 '(Booted)' || true)
          if [ -z "${DEVICE_NAME:-}" ] && [ -n "$BOOTED_LINE" ]; then
            DEVICE_NAME=$(echo "$BOOTED_LINE" | sed -E 's/^[[:space:]]*([^()]+) \(.*/\1/' | xargs)
          fi
          # API_LEVEL left empty if not detected
        fi
      fi
      # Convert each run into a unique output dir, then merge into RUN_DIR
      PART_DIR="${RUN_DIR}-part-$(basename "$TEST_FILE" .dart)-$(date +%H%M%S)-$$"
      mkdir -p "$(dirname "$PART_DIR")"
      convert_xcresult "$LATEST_XCRESULT" "$PART_DIR"
      mkdir -p "$RUN_DIR"
      cp -a "$PART_DIR"/* "$RUN_DIR"/ || true
    fi

    if [ "$RC" -ne 0 ]; then ANY_FAIL=1; fi
  done
else
  echo ">> Running Patrol on: $TARGET (platform: $PLAT)"
  if [ -f "$TARGET" ]; then
    set +e
    patrol test --target "$TARGET" ${PATROL_ARGS[@]+"${PATROL_ARGS[@]}"}
    RC=$?
    set -e
  elif [ -d "$TARGET" ]; then
    # If it's the default integration_test directory, let Patrol discover tests itself
    if [ "$(basename "$TARGET")" = "integration_test" ]; then
      set +e
      patrol test ${PATROL_ARGS[@]+"${PATROL_ARGS[@]}"}
      RC=$?
      set -e
    else
      echo "ERROR: Directory targets other than 'integration_test' are not supported by this script."
      echo "Run a loop externally, e.g.: find $TARGET -name '*_test.dart' -print0 | xargs -0 -n1 $0"
      exit 7
    fi
  fi

  if [ "$PLAT" = "android" ]; then
    mkdir -p "$RUN_DIR"
    # --- ANDROID: COLLECT FROM TEST STORAGE ------------------------------------
    if ! adb ${ADB_TARGET:+-s "$ADB_TARGET"} get-state >/dev/null 2>&1; then
      echo "ERROR: No Android device/emulator detected (adb)."; exit 2
    fi
    echo ">> Pulling Allure results from Android device..."
    adb ${ADB_TARGET:+-s "$ADB_TARGET"} exec-out sh -c 'cd /sdcard/googletest/test_outputfiles && tar cf - allure-results' \
    | tar xvf - -C "$RUN_DIR" --strip-components=1
  else
    # --- IOS: CONVERT XCRESULT WITH allure-xcresult ----------------------------
    echo ">> Locating latest .xcresult..."
    XCRESULT_PATH=${XCRESULT_PATH:-$(find build -maxdepth 3 -name "*.xcresult" -type d -print0 2>/dev/null | xargs -0 ls -1td 2>/dev/null | head -n1)}
    if [ -z "${XCRESULT_PATH:-}" ] || [ ! -d "$XCRESULT_PATH" ]; then
      echo "ERROR: Could not find .xcresult bundle under ./build. Set $XCRESULT_PATH explicitly."; exit 6
    fi
    echo ">> Converting xcresult to Allure results: $XCRESULT_PATH"
    # Populate iOS device info for Allure environment if not provided
    if [ -z "${DEVICE_NAME:-}" ] || [ -z "${API_LEVEL:-}" ]; then
      if command -v python3 >/dev/null 2>&1; then
        IOS_INFO="$(python3 - <<'PY'
import json, subprocess, re
data=json.loads(subprocess.check_output(["xcrun","simctl","list","devices","-j"]))
boot=None; rt=""
for runtime, devices in data.get("devices",{}).items():
    for d in devices:
        if d.get("state")=="Booted":
            boot=d; rt=runtime; break
    if boot: break
name=boot.get("name","" ) if boot else ""
ver=""
m=re.search(r"iOS-(\\d+)-(\\d+)", rt)
if m: ver=f"{m.group(1)}.{m.group(2)}"
print(name)
print(ver)
PY
)"
        IOS_NAME="$(printf "%s" "$IOS_INFO" | sed -n '1p')"
        IOS_VER="$(printf "%s" "$IOS_INFO" | sed -n '2p')"
        DEVICE_NAME=${DEVICE_NAME:-"${IOS_NAME:-iOS Simulator}"}
        API_LEVEL=${API_LEVEL:-"${IOS_VER:-}"}
      else
        BOOTED_LINE=$(xcrun simctl list devices | grep -m1 '(Booted)' || true)
        if [ -z "${DEVICE_NAME:-}" ] && [ -n "$BOOTED_LINE" ]; then
          DEVICE_NAME=$(echo "$BOOTED_LINE" | sed -E 's/^[[:space:]]*([^()]+) \(.*/\1/' | xargs)
        fi
        # API_LEVEL left empty if not detected
      fi
    fi
    # Ensure parent exists, but do NOT pre-create the output directory itself
    mkdir -p "$(dirname "$RUN_DIR")"
    convert_xcresult "$XCRESULT_PATH" "$RUN_DIR"
  fi

  if [ "${RC:-0}" -ne 0 ]; then ANY_FAIL=1; fi
fi

# --- VERIFY WE HAVE RESULTS --------------------------------------------------
shopt -s nullglob
RESULT_FILES=("$RUN_DIR"/*-result.json)
if [ ${#RESULT_FILES[@]} -eq 0 ]; then
  echo "ERROR: No Allure results found in run dir."
  echo "Searched: $RUN_DIR"
  exit 10
fi

# --- OPTIONAL: WAIT FOR SCHEMATHESIS TO FINISH -------------------------------
if [ "${RUN_ST}" = "1" ] && [ -n "${ST_PID:-}" ] && [ "$ST_FINISH_TIMEOUT_SECS" -gt 0 ]; then
  echo ">> Waiting up to ${ST_FINISH_TIMEOUT_SECS}s for Schemathesis to finish…"
  SECS=0
  while kill -0 "$ST_PID" 2>/dev/null; do
    sleep 2; SECS=$((SECS+2))
    if [ $SECS -ge "$ST_FINISH_TIMEOUT_SECS" ]; then
      echo "WARN: Schemathesis still running; continue."
      break
    fi
  done
fi

# --- IMPORT SCHEMATHESIS ARTIFACTS INTO ALLURE (optional) -------------------
if [ "${IMPORT_ST_INTO_PATROL:-1}" = "1" ]; then
  import_schemathesis_into_allure
fi

# --- ADD ENVIRONMENT PANEL ---------------------------------------------------
echo ">> Writing environment.properties..."
APP_VERSION=${APP_VERSION:-""}
FLAVOR=${FLAVOR:-""}
DEVICE_NAME=${DEVICE_NAME:-""}
API_LEVEL=${API_LEVEL:-""}
GIT_SHA=${GIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo "")}
BASE_URL=${BASE_URL:-""}

if [ "$PLAT" = "android" ]; then
  DEVICE_NAME=${DEVICE_NAME:-"$(adb ${ADB_TARGET:+-s "$ADB_TARGET"} shell getprop ro.product.manufacturer | tr -d '\r') $(adb ${ADB_TARGET:+-s "$ADB_TARGET"} shell getprop ro.product.model | tr -d '\r')"}
  API_LEVEL=${API_LEVEL:-"$(adb ${ADB_TARGET:+-s "$ADB_TARGET"} shell getprop ro.build.version.sdk | tr -d '\r')"}
fi

cat > "$RUN_DIR/environment.properties" <<EOF
appVersion=${APP_VERSION}
flavor=${FLAVOR}
device=${DEVICE_NAME}
apiLevel=${API_LEVEL}
gitSha=${GIT_SHA}
baseUrl=${BASE_URL}
EOF

# --- ADD CATEGORIES (FAILURE BUCKETS) ---------------------------------------
cat > "$RUN_DIR/categories.json" <<'EOF'
[
  {"name":"App crashes","matchedStatuses":["failed"],"messageRegex":".*Fatal Exception.*"},
  {"name":"UI not found","matchedStatuses":["failed"],"messageRegex":".*findsOneWidget.*"},
  {"name":"Network/timeout","matchedStatuses":["failed"],"messageRegex":".*(Timeout|SocketException).*"}
]
EOF

# --- PRESERVE HISTORY --------------------------------------------------------
if [ -d "$REPORT_DIR/history" ]; then
  echo ">> Preserving history from previous report..."
  cp -r "$REPORT_DIR/history" "$RUN_DIR/" || true
fi

# --- PREPARE EXECUTOR METADATA FOR SCHEMATHESIS DEEPLINK --------------------
if [ -d "build/allure-report-schemathesis" ]; then
  EXEC_NAME="${ST_URL:-Patrol E2E}"
  cat > "$RUN_DIR/executor.json" <<EOF
{
  "name": "$EXEC_NAME",
  "buildName": "API Contracts Test",
  "reportUrl": "schemathesis/index.html",
  "buildUrl": "schemathesis/index.html"
}
EOF
fi

# --- GENERATE & (OPTIONALLY) SERVE REPORT ------------------------------------
echo ">> Generating Allure report..."
allure generate "$RUN_DIR" -o "$REPORT_DIR" --clean
echo ">> Static report available at: $REPORT_DIR/index.html"

# --- LINK SEPARATE SCHEMATHESIS REPORT, IF PRESENT --------------------------
if [ -d "build/allure-report-schemathesis" ]; then
  echo ">> Linking Schemathesis report into Patrol report..."
  rm -rf "$REPORT_DIR/schemathesis" || true
  cp -r "build/allure-report-schemathesis" "$REPORT_DIR/schemathesis"
fi

if [ "$SERVE_REPORT" = "1" ]; then
  echo ">> Serving Allure report (Ctrl+C to stop)..."
  allure serve "$RUN_DIR"
fi
