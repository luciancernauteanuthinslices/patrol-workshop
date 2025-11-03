#!/bin/bash
set -euo pipefail

: "${BROWSERSTACK_USERNAME:?}"
: "${BROWSERSTACK_ACCESS_KEY:?}"

FLAVOR="${FLAVOR:-prod}"
TARGET="${TARGET:-integration_test/quiz_test.dart}"

# Build app + androidTest via Patrol (correct variant)
patrol build android --target "$TARGET" --flavor "$FLAVOR"

APP_APK="build/app/outputs/apk/${FLAVOR}/debug/app-${FLAVOR}-debug.apk"
TEST_APK="build/app/outputs/apk/androidTest/${FLAVOR}/debug/app-${FLAVOR}-debug-androidTest.apk"

test -f "$APP_APK"
test -f "$TEST_APK"

# ---- Upload APP (Flutter endpoint)
APP_UPLOAD=$(curl -s -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/app" \
  -F "file=@${APP_APK}")
APP_URL=$(printf '%s' "$APP_UPLOAD" | sed -n 's/.*"app_url":"\([^"]*\)".*/\1/p')
if [[ -z "$APP_URL" ]]; then
  echo "Failed to upload Android app to BrowserStack. Response:" >&2
  echo "$APP_UPLOAD" >&2
  exit 3
fi

# ---- Upload TEST SUITE (Flutter endpoint)
TEST_UPLOAD=$(curl -s -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/test-suite" \
  -F "file=@${TEST_APK}")
TEST_URL=$(printf '%s' "$TEST_UPLOAD" | sed -n 's/.*"test_suite_url":"\([^"]*\)".*/\1/p')
if [[ -z "$TEST_URL" ]]; then
  echo "Failed to upload Android test-suite to BrowserStack. Response:" >&2
  echo "$TEST_UPLOAD" >&2
  exit 4
fi

# ---- Start BUILD (Flutter endpoint)
DEVICES="${DEVICES:-[\"Google Pixel 7-13.0\"]}"
PROJECT="${PROJECT:-patrol_workshop}"
if [[ -n "${BUILD_TAG:-}" ]]; then
  BODY=$(printf '{"app":"%s","testSuite":"%s","project":"%s","devices":%s,"buildTag":"%s"}' \
  "$APP_URL" "$TEST_URL" "$PROJECT" "$DEVICES" "$BUILD_TAG")
else
  BODY=$(printf '{"app":"%s","testSuite":"%s","project":"%s","devices":%s}' \
  "$APP_URL" "$TEST_URL" "$PROJECT" "$DEVICES")
fi

RESP=$(curl -s -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" \
  -H "Content-Type: application/json" \
  -X POST "https://api-cloud.browserstack.com/app-automate/espresso/v2/build" \
  -d "$BODY")

BUILD_ID=$(printf '%s' "$RESP" | sed -n 's/.*"build_id":"\([^"]*\)".*/\1/p')
if [[ -z "$BUILD_ID" ]]; then
  echo "Failed to start Flutter build on BrowserStack. Response:" >&2
  echo "$RESP" >&2
  exit 5
fi

echo "$BUILD_ID"
