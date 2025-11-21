# Schemathesis Token Export

This document describes how a Bearer token is exported from the app under test for use with Schemathesis, and how to run both Patrol E2E tests and Schemathesis safely.

## Overview
- Export is opt-in and gated by a compile-time flag: `--dart-define=EXPORT_TOKEN=true`.
- The token is written to the app's sandbox (no logs printed).
- You can pull it to the host via Android `adb run-as` or iOS Simulator `xcrun simctl`, then pass it to Schemathesis as an `Authorization` header.

## Changes in this repo
- Added helper: `lib/testing/token_export.dart`
    ```dart
    import 'dart:io';
    import 'package:path_provider/path_provider.dart';
    import 'package:path/path.dart' as p;

    const bool kExportForSchemathesis =
        bool.fromEnvironment('EXPORT_TOKEN', defaultValue: false);

    class TokenExport {
    static Future<void> save(String token) async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, '.schemathesis_token'));
        await file.writeAsString(token, flush: true);
    }
    }
    ```
    - Provides `TokenExport.save(token)` and `kExportForSchemathesis` constant.
    - Wired export in: `lib/infrastructure/auth/auth_service.dart`
        ```dart
        // Schemathesis token export
            // debug only
            log("access_token: ${session!.getAccessToken().getJwtToken()}");

            // Export token for Schemathesis if requested via --dart-define
            if (kExportForSchemathesis) {
                await TokenExport.save(session.getAccessToken().getJwtToken()!);
            }
        ```
        
  - After a successful Cognito login, if `kExportForSchemathesis` is true, writes the token to a sandbox file.
  - Rationale:
    - `AuthService.login` is the single, centralized place where the Cognito session (and thus the JWT access token) is obtained.
    - Exporting here guarantees it happens exactly once, immediately after a successful login, independent of specific UI flows.
    - The compile-time flag keeps this behavior strictly test-only; production builds remain unaffected.

- Script: `integration_test/run_patrol_allure.sh`
  - If `EXPORT_TOKEN` env var is set (and not `0`/`false`), forwards `--dart-define=EXPORT_TOKEN=true` to Patrol.
- Dependencies:
  - `pubspec.yaml`: added `path_provider` (token file path).
- Git ignore:
  - `.gitignore`: added `.schemathesis_token` (host-side copy of the token).

## File paths
- In-app sandbox file: `/data/data/<pkg>/app_flutter/.schemathesis_token` (Android)
- Host copy: `./.schemathesis_token` (ignored by Git)

## Prerequisites
- Patrol CLI and Allure CLI installed (see docs/Allure_Reporting_Guide.md).
- Android emulator/device connected via `adb`.
- For iOS Simulator: Xcode + Command Line Tools installed (for `xcrun simctl`) and a booted simulator.
- Flutter dependencies fetched:
  ```bash
  flutter pub get
  ```

## Export the token during Patrol run
- Using the wrapper script (recommended):
  ```bash
  TAGS=smoke EXPORT_TOKEN=1 ./integration_test/run_patrol_allure.sh
  ```
  - To exclude other tags (e.g., regression):
    ```bash
    TAGS=smoke EXCLUDE_TAGS=regression EXPORT_TOKEN=1 ./integration_test/run_patrol_allure.sh
    ```
- Or, direct Patrol invocation:
  ```bash
  patrol test --dart-define=EXPORT_TOKEN=true --tags smoke
  ```

The token will be exported only after a successful login in your flow.

## Pull the token to the host (Android)
```bash
PKG="com.thinslices.solarisdemo"  # App package id from pubspec.yaml (patrol.android.package_name)

# Verify token file exists (silent)
adb shell run-as "$PKG" ls /data/data/$PKG/app_flutter/.schemathesis_token >/dev/null 2>&1

# Pull to host without logging secrets
adb exec-out run-as "$PKG" cat /data/data/$PKG/app_flutter/.schemathesis_token > .schemathesis_token

# Export header for Schemathesis
export AUTH_HEADER="Authorization: Bearer $(cat .schemathesis_token)"
export BEARER_TOKEN="$(cat .schemathesis_token)"  # Optional separate var
echo "${AUTH_HEADER:0:32}..."  # Optional sanity check without printing the full token
```

Tip: `.schemathesis_token` is ignored by Git via `.gitignore`.

## Pull the token to the host (iOS Simulator)
```bash
# Ensure your app is installed/launched on a booted simulator and that the login flow ran with EXPORT_TOKEN=1

# Preferred: use the helper script
BUNDLE_ID="com.thinslices.solarisdemo" \
  bash integration_test/ios_pull_token.sh

# Then export the header for Schemathesis
export AUTH_HEADER="Authorization: Bearer $(cat .schemathesis_token)"
export BEARER_TOKEN="$(cat .schemathesis_token)"  # Optional separate var
echo "${AUTH_HEADER:0:32}..."  # Optional sanity check without printing the full token

# Manual (alternative):
DEVICE_UDID=$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}')
APP_CONTAINER=$(xcrun simctl get_app_container "$DEVICE_UDID" "$BUNDLE_ID" data)
cp -f "$APP_CONTAINER/Documents/.schemathesis_token" ./.schemathesis_token
```

## Run Schemathesis
```bash
./integration_test/myenv/bin/schemathesis run openapi-docs.yaml \
  -u "https://jsxhc7emf3.execute-api.eu-west-1.amazonaws.com" \
  -H "$AUTH_HEADER" \
  --exclude-deprecated \
  --phases examples,coverage \
  --mode all \
  -n 5 -w auto \
  --report=junit --report-dir integration_test/schemathesis-report
```

Additional useful options:
- **Filter by endpoint** (narrow the scope):
  ```bash
  ./integration_test/myenv/bin/schemathesis run openapi-docs.yaml 
  -u "https://jsxhc7emf3.execute-api.eu-west-1.amazonaws.com" 
  -H "$AUTH_HEADER" --endpoint "/account/cards/{card_id}/block"
  ```
- **Run by operationId(s)**:
  ```bash
  ./integration_test/myenv/bin/schemathesis run openapi-docs.yaml 
  -u "https://jsxhc7emf3.execute-api.eu-west-1.amazonaws.com" -H "$AUTH_HEADER" 
  --operation-id getScheduledNotifications
  ```
- **Save JUnit report** (already shown) and check it under `integration_test/schemathesis-report/`.

## iOS note
- iOS Simulator is supported via the included helper: `integration_test/ios_pull_token.sh` (uses `xcrun simctl`).
- Physical iOS devices are not covered here; retrieving sandbox files requires Xcode or specialized tooling and is outside the scope of this doc.

## Security considerations
- No secrets are printed to logs; writes go directly to a sandbox file.
- Host-side token file is ignored by Git.
- Only exported when explicitly enabled via `--dart-define` (or `EXPORT_TOKEN=1` with the wrapper).

## Disable
- Simply omit the flag: do not set `EXPORT_TOKEN` and do not pass `--dart-define=EXPORT_TOKEN=true`.
