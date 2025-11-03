#!/bin/bash
set -euo pipefail
: "${BROWSERSTACK_USERNAME:?}"
: "${BROWSERSTACK_ACCESS_KEY:?}"
FLAVOR="${FLAVOR:-prod}"
TARGET="integration_test/quiz_test.dart"
# Build Patrol iOS integration artifacts (Runner.app and RunnerUITests-Runner.app)
patrol build ios --target "$TARGET" --release --flavor "$FLAVOR"
# Locate the test runner app
PRODUCTS_DIR="build/ios_integ/Build/Products"
RUNNER_UI_APP=$(find "$PRODUCTS_DIR" -type d -name 'RunnerUITests-Runner.app' | head -n1)
if [[ -z "${RUNNER_UI_APP}" ]]; then
  echo "RunnerUITests-Runner.app not found under $PRODUCTS_DIR" >&2
  exit 1
fi
TEST_ZIP_DIR=$(dirname "$RUNNER_UI_APP")
TEST_ZIP_PATH="$TEST_ZIP_DIR/xcuitest-testsuite.zip"
(
  cd "$TEST_ZIP_DIR"
  rm -f "$(basename "$TEST_ZIP_PATH")"
  zip --symlinks -r "$(basename "$TEST_ZIP_PATH")" "$(basename "$RUNNER_UI_APP")" >/dev/null
)
# Determine AUT .ipa path
IPA_PATH="${IPA_PATH:-}"
if [[ -z "$IPA_PATH" ]]; then
  # Try to build an .ipa for the AUT using Flutter (requires signing)
  if flutter --version >/dev/null 2>&1; then
    set +e
    flutter build ipa --flavor "$FLAVOR" >/dev/null 2>&1
    BUILD_STATUS=$?
    set -e
    if [[ $BUILD_STATUS -eq 0 ]]; then
      CANDIDATE_IPA=$(ls -1 build/ios/ipa/*.ipa 2>/dev/null | head -n1 || true)
      if [[ -n "$CANDIDATE_IPA" ]]; then
        IPA_PATH="$CANDIDATE_IPA"
      fi
    fi
  fi
fi
if [[ -z "$IPA_PATH" ]]; then
  echo "No .ipa found (Flutter code signing/export is required). Ensure an .ipa is available at build/ios/ipa/*.ipa and re-run." >&2
  exit 2
fi
# Upload app (.ipa) and test-suite (.zip) to BrowserStack
APP_UPLOAD=$(curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" -s -X POST "https://api-cloud.browserstack.com/app-automate/xcuitest/v2/app" -F "file=@${IPA_PATH}")
APP_URL=$(printf '%s' "$APP_UPLOAD" | sed -n 's/.*"app_url":"\([^"]*\)".*/\1/p')
TEST_UPLOAD=$(curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" -s -X POST "https://api-cloud.browserstack.com/app-automate/xcuitest/v2/test-suite" -F "file=@${TEST_ZIP_PATH}")
TEST_URL=$(printf '%s' "$TEST_UPLOAD" | sed -n 's/.*"test_suite_url":"\([^"]*\)".*/\1/p')
DEVICES="${DEVICES:-[\"iPhone 12-16\"]}"
PROJECT="${PROJECT:-patrol_workshop}"
BODY=$(printf '{"app":"%s","testSuite":"%s","project":"%s","devices":%s}' "$APP_URL" "$TEST_URL" "$PROJECT" "$DEVICES")
RESP=$(curl -u "$BROWSERSTACK_USERNAME:$BROWSERSTACK_ACCESS_KEY" -s -X POST "https://api-cloud.browserstack.com/app-automate/xcuitest/v2/build" -H "Content-Type: application/json" -d "$BODY")
BUILD_ID=$(printf '%s' "$RESP" | sed -n 's/.*"build_id":"\([^"]*\)".*/\1/p')
echo "$BUILD_ID"
