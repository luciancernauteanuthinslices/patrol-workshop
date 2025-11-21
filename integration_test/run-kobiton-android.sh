#!/bin/bash
set -euo pipefail

[ -f ".kobiton_auth" ] && source .kobiton_auth

: "${KOBITON_USERNAME:?}"
: "${KOBITON_API_KEY:?}"

FLAVOR="${FLAVOR:-prod}"
TARGET="${TARGET:-integration_test/quiz_test.dart}"

patrol build android --target "$TARGET" --flavor "$FLAVOR"

APP_APK="build/app/outputs/apk/${FLAVOR}/debug/app-${FLAVOR}-debug.apk"
TEST_APK="build/app/outputs/apk/androidTest/${FLAVOR}/debug/app-${FLAVOR}-debug-androidTest.apk"

test -f "$APP_APK"
test -f "$TEST_APK"

AUTH="$(printf "%s:%s" "$KOBITON_USERNAME" "$KOBITON_API_KEY" | base64)"

TR_UP=$(curl -s -X POST "https://api.kobiton.com/v1/testRunner/uploadUrl" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "$(printf '{"runnerName":"%s"}' "$(basename "$TEST_APK")")")

TR_URL=$(printf '%s' "$TR_UP" | sed -n 's/.*"uploadUrl":"\([^"]*\)".*/\1/p')
TR_PATH=$(printf '%s' "$TR_UP" | sed -n 's/.*"runnerPath":"\([^"]*\)".*/\1/p')
if [[ -z "$TR_URL" || -z "$TR_PATH" ]]; then
  echo "Failed to get testRunner upload URL from Kobiton" >&2
  echo "$TR_UP" >&2
  exit 10
fi

curl -s -X PUT "$TR_URL" -H "Content-Type: application/octet-stream" -H "x-amz-tagging: unsaved=true" -T "$TEST_APK" >/dev/null

TR_DL=$(curl -s -X POST "https://api.kobiton.com/v1/testRunner/downloadUrl" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "$(printf '{"runnerPath":"%s"}' "$TR_PATH")")

TEST_RUNNER_URL=$(printf '%s' "$TR_DL" | sed -n 's/.*"downloadUrl":"\([^"]*\)".*/\1/p')
if [[ -z "$TEST_RUNNER_URL" ]]; then
  echo "Failed to get testRunner download URL from Kobiton" >&2
  echo "$TR_DL" >&2
  exit 11
fi

APP_UP=$(curl -s -X POST "https://api.kobiton.com/v2/apps/upload-url" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "$(printf '{"file_name":"%s"}' "$(basename "$APP_APK")")")

APP_S3=$(printf '%s' "$APP_UP" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
APP_PATH=$(printf '%s' "$APP_UP" | sed -n 's/.*"app_path":"\([^"]*\)".*/\1/p')

if [[ -z "$APP_S3" || -z "$APP_PATH" ]]; then
  echo "Failed to get app upload URL from Kobiton" >&2
  echo "$APP_UP" >&2
  exit 12
fi

curl -s -X PUT "$APP_S3" -H "Content-Type: application/octet-stream" -H "x-amz-tagging: unsaved=true" -T "$APP_APK" >/dev/null

APP_CREATE=$(curl -s -X POST "https://api.kobiton.com/v2/apps" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "$(printf '{"file_name":"%s","app_path":"%s"}' "$(basename "$APP_APK")" "$APP_PATH")")

APP_ID=$(printf '%s' "$APP_CREATE" | sed -n 's/.*"app_id":\s*\([0-9]*\).*/\1/p')
VERSION_ID=$(printf '%s' "$APP_CREATE" | sed -n 's/.*"version_id":\s*\([0-9]*\).*/\1/p')

# Some responses return null appId while processing; poll v2 parsing-status using versionId
if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  if [[ -n "$VERSION_ID" ]]; then
    for i in {1..30}; do
      PARSE_STATUS=$(curl -s -X GET "https://api.kobiton.com/v2/apps/parsing-status?appVersionId=${VERSION_ID}" \
        -H "Authorization: Basic $AUTH")
      APP_ID=$(printf '%s' "$PARSE_STATUS" | sed -n 's/.*"app_id":\s*\([0-9]*\).*/\1/p')
      STATE=$(printf '%s' "$PARSE_STATUS" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
      if [[ -n "$APP_ID" ]]; then
        break
      fi
      if [[ "$STATE" == "FAILURE_PARSING" ]]; then
        echo "Kobiton failed to parse uploaded app. Response:" >&2
        echo "$PARSE_STATUS" >&2
        exit 13
      fi
      sleep 2
    done
  fi
fi

if [[ -z "$APP_ID" ]]; then
  echo "Failed to create app in Kobiton" >&2
  echo "$APP_CREATE" >&2
  exit 13
fi

DEVICE_NAME="${KOBITON_DEVICE_NAME:-2201117TY}"
PLATFORM_VERSION="${KOBITON_PLATFORM_VERSION:-13}"
TEST_FRAMEWORK="${KOBITON_TEST_FRAMEWORK:-UIAUTOMATOR}"
SESSION_NAME="${SESSION_NAME:-patrol_android}"
UDID="${KOBITON_UDID:-}"
AUTO_DEVICE="${KOBITON_AUTO_DEVICE:-}"
DEVICE_GROUP="${KOBITON_DEVICE_GROUP:-KOBITON}"

# If UIAUTOMATOR and UDID provided, attempt to resolve proper deviceName/platformVersion via Devices API
if [[ "$TEST_FRAMEWORK" == "UIAUTOMATOR" && -n "$UDID" ]]; then
  DEVINFO=$(curl -s -X GET "https://api.kobiton.com/v1/devices/${UDID}" \
    -H "Authorization: Basic $AUTH" -H "Accept: application/json")
  RESOLVED_NAME=$(printf '%s' "$DEVINFO" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
  if [[ -z "$RESOLVED_NAME" ]]; then
    RESOLVED_NAME=$(printf '%s' "$DEVINFO" | sed -n 's/.*"deviceName":"\([^"]*\)".*/\1/p')
  fi
  RESOLVED_PV=$(printf '%s' "$DEVINFO" | sed -n 's/.*"platformVersion":"\([^"]*\)".*/\1/p')
  if [[ -n "$RESOLVED_NAME" ]]; then
    DEVICE_NAME="$RESOLVED_NAME"
  fi
  if [[ -n "$RESOLVED_PV" ]]; then
    PLATFORM_VERSION="$RESOLVED_PV"
  fi
  echo "Using device resolved from UDID: name=$DEVICE_NAME, platformVersion=$PLATFORM_VERSION" >&2
fi

# Prefer a direct download URL for the AUT if available; otherwise use version reference
APP_FIELD="kobiton-store:v$VERSION_ID"
APP_DL=$(curl -s -G "https://api.kobiton.com/v1/apps/downloadUrl" \
  -H "Authorization: Basic $AUTH" -H "Accept: application/json" \
  --data-urlencode "appPath=$APP_PATH" || true)
APP_DOWNLOAD_URL=$(printf '%s' "$APP_DL" | sed -n 's/.*"downloadUrl":"\([^"]*\)".*/\1/p')
if [[ -n "$APP_DOWNLOAD_URL" ]]; then
  APP_FIELD="$APP_DOWNLOAD_URL"
fi

if [[ "$TEST_FRAMEWORK" == "UIAUTOMATOR" ]]; then
  if [[ "$AUTO_DEVICE" == "1" ]]; then
    BODY=$(printf '{"session_name":"%s","session_description":"Patrol Flutter test","test_framework":"%s","app":"%s","test_runner":"%s","device_name":"*","platform_version":"*"}' \
      "$SESSION_NAME" "$TEST_FRAMEWORK" "$APP_FIELD" "$TEST_RUNNER_URL")
  elif [[ -n "$UDID" ]]; then
    BODY=$(printf '{"session_name":"%s","session_description":"Patrol Flutter test","test_framework":"%s","app":"%s","test_runner":"%s","udid":"%s"}' \
      "$SESSION_NAME" "$TEST_FRAMEWORK" "$APP_FIELD" "$TEST_RUNNER_URL" "$UDID")
  else
    BODY=$(printf '{"session_name":"%s","session_description":"Patrol Flutter test","test_framework":"%s","app":"%s","test_runner":"%s","device_name":"%s","platform_version":"%s"}' \
      "$SESSION_NAME" "$TEST_FRAMEWORK" "$APP_FIELD" "$TEST_RUNNER_URL" "$DEVICE_NAME" "$PLATFORM_VERSION")
  fi
else
  if [[ -n "$UDID" ]]; then
    BODY=$(printf '{"configuration":{"sessionName":"%s","udid":"%s","deviceGroup":"%s","app":"kobiton-store:%s","testRunner":"%s","testFramework":"%s","sessionTimeout":30}}' \
      "$SESSION_NAME" "$UDID" "$DEVICE_GROUP" "$APP_ID" "$TEST_RUNNER_URL" "$TEST_FRAMEWORK")
  else
    BODY=$(printf '{"configuration":{"sessionName":"%s","deviceName":"%s","platformVersion":"%s","deviceGroup":"%s","app":"kobiton-store:%s","testRunner":"%s","testFramework":"%s","sessionTimeout":30}}' \
      "$SESSION_NAME" "$DEVICE_NAME" "$PLATFORM_VERSION" "$DEVICE_GROUP" "$APP_ID" "$TEST_RUNNER_URL" "$TEST_FRAMEWORK")
  fi
fi

HUB_SESSION_URL="https://api.kobiton.com/hub/session"
if [[ "$TEST_FRAMEWORK" == "UIAUTOMATOR" ]]; then
  HUB_SESSION_URL="https://api.kobiton.com/v2/sessions/native"
else
  if [[ -n "${SERVER_URL:-}" ]]; then
    case "$SERVER_URL" in
      */wd/hub)
        HUB_SESSION_URL="${SERVER_URL%/wd/hub}/hub/session"
        ;;
      */hub/session)
        HUB_SESSION_URL="$SERVER_URL"
        ;;
      */hub)
        HUB_SESSION_URL="$SERVER_URL/session"
        ;;
    esac
  fi
fi

RESP=$(curl -s -X POST "$HUB_SESSION_URL" \
  -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" -H "Accept: application/json" \
  -d "$BODY")

if [[ "$TEST_FRAMEWORK" == "UIAUTOMATOR" ]]; then
  SESSION_ID=$(printf '%s' "$RESP" | sed -n 's/.*"id":\s*\([0-9]*\).*/\1/p')
else
  SESSION_ID=$(printf '%s' "$RESP" | sed -n 's/.*"kobitonSessionId":\s*\([0-9]*\).*/\1/p')
fi
if [[ -z "$SESSION_ID" ]]; then
  echo "Failed to start Kobiton session" >&2
  echo "HUB_SESSION_URL: $HUB_SESSION_URL" >&2
  echo "BODY: $BODY" >&2
  echo "$RESP" >&2
  exit 14
fi

echo "$SESSION_ID"
