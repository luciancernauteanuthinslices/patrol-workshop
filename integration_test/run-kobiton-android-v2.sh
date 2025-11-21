#!/bin/bash
set -euo pipefail

# Kobiton Android runner with Appium Flutter driver
# API v2 for App Repository: https://docs.kobiton.com/apps/upload-an-app/using-the-kobiton-api

[ -f ".kobiton_auth" ] && source .kobiton_auth

: "${KOBITON_USERNAME:?}"
: "${KOBITON_API_KEY:?}"

FLAVOR="${FLAVOR:-prod}"
TARGET="${TARGET:-integration_test/quiz_test.dart}"
SESSION_NAME="${SESSION_NAME:-patrol_android}"
DEVICE_NAME="${KOBITON_DEVICE_NAME:-*}"
PLATFORM_VERSION="${KOBITON_PLATFORM_VERSION:-*}"
AUTH="$(printf "%s:%s" "$KOBITON_USERNAME" "$KOBITON_API_KEY" | base64)"

# Build APKs
echo "Building Android APKs..."
patrol build android --target "$TARGET" --flavor "$FLAVOR"

APP_APK="build/app/outputs/apk/${FLAVOR}/debug/app-${FLAVOR}-debug.apk"
test -f "$APP_APK" || { echo "App APK not found"; exit 1; }

# Upload app to Kobiton
echo "Uploading app to Kobiton..."
APP_UP=$(curl -s -X POST "https://api.kobiton.com/v2/apps/upload-url" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" \
  -d "{\"file_name\":\"$(basename "$APP_APK")\"}")

APP_S3=$(printf '%s' "$APP_UP" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
APP_PATH=$(printf '%s' "$APP_UP" | sed -n 's/.*"app_path":"\([^"]*\)".*/\1/p')
[[ -z "$APP_S3" || -z "$APP_PATH" ]] && { echo "Failed to get upload URL: $APP_UP"; exit 12; }

curl -s -X PUT "$APP_S3" -H "Content-Type: application/octet-stream" -H "x-amz-tagging: unsaved=true" -T "$APP_APK" >/dev/null

APP_CREATE=$(curl -s -X POST "https://api.kobiton.com/v2/apps" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" \
  -d "{\"file_name\":\"$(basename "$APP_APK")\",\"app_path\":\"$APP_PATH\"}")

VERSION_ID=$(printf '%s' "$APP_CREATE" | sed -n 's/.*"version_id":\s*\([0-9]*\).*/\1/p')
[[ -z "$VERSION_ID" ]] && { echo "Failed to create app: $APP_CREATE"; exit 13; }

# Wait for app parsing
echo "Waiting for app parsing..."
for i in {1..15}; do
  PARSE_STATUS=$(curl -s -X GET "https://api.kobiton.com/v2/apps/parsing-status?appVersionId=${VERSION_ID}" -H "Authorization: Basic $AUTH")
  STATE=$(printf '%s' "$PARSE_STATUS" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
  [[ "$STATE" == "OK" ]] && { echo "✓ App parsing completed"; break; }
  [[ "$STATE" == "FAILURE_PARSING" ]] && { echo "App parsing failed: $PARSE_STATUS"; exit 14; }
  echo "  Attempt $i: $STATE"
  sleep 3
done

[[ "$STATE" != "OK" ]] && echo "Warning: Parsing incomplete ($STATE), proceeding anyway..."

APP_REF="kobiton-store:v$VERSION_ID"

# Start Appium session with Flutter driver
echo "Starting Appium session..."
BODY=$(cat <<JSON
{
  "desiredCapabilities":{
    "sessionName":"$SESSION_NAME",
    "sessionDescription":"Patrol Flutter test",
    "deviceName":"$DEVICE_NAME",
    "platformVersion":"$PLATFORM_VERSION",
    "platformName":"Android",
    "deviceGroup":"KOBITON",
    "app":"$APP_REF",
    "automationName":"UiAutomator2",
    "autoAcceptAlerts":true,
    "autoGrantPermissions":true,
    "grantPermissions":true,
    "noReset":false,
    "fullReset":false,
    "skipDeviceInitialization":false,
    "skipServerInstallation":false,
    "adbExecTimeout":60000,
    "androidInstallTimeout":90000,
    "newCommandTimeout":1800
  }
}
JSON
)

HUB_URL="${SERVER_URL:-https://api.kobiton.com/wd/hub}/session"

RESP=$(curl -s -w "\n%{http_code}" -X POST "$HUB_URL" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" \
  -d "$BODY")

HTTP_CODE=$(echo "$RESP" | tail -1)
RESP_BODY=$(echo "$RESP" | head -n -1 2>/dev/null || echo "$RESP" | sed '$d')

# Extract session ID
SESSION_ID=$(printf '%s' "$RESP_BODY" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')
[[ -z "$SESSION_ID" ]] && SESSION_ID=$(printf '%s' "$RESP_BODY" | sed -n 's/.*"kobitonSessionId":\s*\([0-9]*\).*/\1/p')

if [[ -z "$SESSION_ID" ]]; then
  echo "Failed to start Appium session (HTTP $HTTP_CODE)"
  echo "Response: $RESP_BODY"
  exit 16
fi

echo "✓ Appium session started: $SESSION_ID"
echo "  View session: https://portal.kobiton.com/sessions/$SESSION_ID"
