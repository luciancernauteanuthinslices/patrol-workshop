#!/usr/bin/env bash
set -euo pipefail

# Pull .schemathesis_token from a booted iOS Simulator's app container
# Usage (from repo root):
#   BUNDLE_ID=com.example.app bash integration_test/allure_schemathesis_reporting/sct_auth/ios_pull_token.sh

BUNDLE_ID=${BUNDLE_ID:-}
DEVICE_UDID=${DEVICE_UDID:-}

if [[ -z "${BUNDLE_ID}" ]]; then
  echo "Error: BUNDLE_ID is required (e.g., com.example.app)." >&2
  exit 1
fi

if [[ -z "${DEVICE_UDID}" ]]; then
  DEVICE_UDID=$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}') || true
fi

if [[ -z "${DEVICE_UDID}" ]]; then
  echo "Error: No booted iOS simulator found. Boot one (e.g., via Xcode) or set DEVICE_UDID." >&2
  exit 1
fi

echo ">> Using simulator UDID: ${DEVICE_UDID}" >&2

APP_CONTAINER=$(xcrun simctl get_app_container "${DEVICE_UDID}" "${BUNDLE_ID}" data 2>/dev/null || true)
if [[ -z "${APP_CONTAINER}" ]]; then
  echo "Error: App container not found for bundle '${BUNDLE_ID}' on simulator '${DEVICE_UDID}'." >&2
  echo "Hint: Ensure the app is installed/launched on this simulator and that tests ran with EXPORT_TOKEN=1." >&2
  exit 1
fi

TOKEN_PATH="${APP_CONTAINER}/Documents/.schemathesis_token"
if [[ ! -f "${TOKEN_PATH}" ]]; then
  echo "Error: Token file not found at: ${TOKEN_PATH}" >&2
  echo "Hint: Make sure login succeeded and token export is enabled (EXPORT_TOKEN=1)." >&2
  exit 2
fi

cp -f "${TOKEN_PATH}" ./.schemathesis_token

echo ">> Pulled token to ./.schemathesis_token" >&2
if command -v wc >/dev/null 2>&1; then
  SIZE=$(wc -c < ./.schemathesis_token)
  echo ">> Token size: ${SIZE} bytes" >&2
fi
