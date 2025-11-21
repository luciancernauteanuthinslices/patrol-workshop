# Allure Reporting: End-to-End Guide (Android + iOS + Patrol)

This guide documents the Allure setup and workflow added to this project, including Android/iOS configuration, how to run tests, collect results, generate/serve reports, trends/history, tagging, environment metadata, and log capture. It also notes how failures are captured and visible in Allure.

## Contents
- Overview
- Android configuration
- iOS configuration (allure-xcresult)
- Run script (single, all, by tags) and environment
- What gets captured (including failures)
- Trends and history
- Tags and filtering
- Useful commands
- Notes and pitfalls

## Overview
- Android instrumentation tests run via Patrol and output Allure results into device TestStorage.
- iOS tests are run via Patrol; the resulting .xcresult bundle is converted to Allure format via allure-xcresult.
- A unified script `integration_test/run_patrol_allure.sh` runs Patrol, collects results, writes environment and categories metadata, preserves history, and generates/serves the Allure report.

## Android configuration

### testInstrumentationRunner
Set in `android/app/build.gradle`:
```groovy
testInstrumentationRunner = "com.thinslices.solarisdemo.AllurePatrolJUnitRunner"
```

### Allure dependencies (androidTest)
```groovy
androidTestImplementation "io.qameta.allure:allure-kotlin-model:2.4.0"
androidTestImplementation "io.qameta.allure:allure-kotlin-commons:2.4.0"
androidTestImplementation "io.qameta.allure:allure-kotlin-junit4:2.4.0"
androidTestImplementation "io.qameta.allure:allure-kotlin-android:2.4.0"
```

### UiAutomator (pinned to satisfy transitive versions):
```groovy
androidTestImplementation "androidx.test.uiautomator:uiautomator:2.2.0"
```

### Orchestrator (optional but recommended):
```groovy
androidTestUtil "androidx.test:orchestrator:1.5.1"
```

### Allure properties (orchestrator/test storage)
Create `android/app/src/androidTest/resources/allure.properties`:
```properties
allure.results.useTestStorage=true
```

### Android test harness rules
`MainActivityTest.java` includes:
- `ScreenshotRule(ScreenshotRule.Mode.END, "ss_end")` (always attach a screenshot at test end)
- `WindowHierarchyRule()` (view hierarchy snapshot)
- `FilteredLogcatRule()` (logcat on failures with noise reduced)
- `AllureEnrichmentRule()` (labels, links, parameters, attachments)

### Android helper code (key files)
- `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureEnrichmentRule.kt`  
  Sets labels: suite=Patrol, feature=Mobile E2E, severity=critical, owner=QA Team  
  Adds links from env vars: GIT_SHA (commit), TMS_ID  
  Adds parameters: device, API level, flavor (from env), env (from env)  
  Optional attachments from env: PATROL_CONFIG_JSON, FEATURE_FLAGS_TEXT  
  Notes:  
  - Use string severity (e.g., "critical") to avoid enum imports across modules.  
  - Avoid BuildConfig.FLAVOR in androidTest; read FLAVOR from environment.

- `android/app/src/androidTest/java/com/thinslices/solarisdemo/FilteredLogcatRule.kt`  
  Clears logcat before each test; on failure, attaches filtered logcat (by PID or tags).  
  Uses UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()) (no internal API).  
  Default filters: level=I, tags=Flutter/Patrol/AndroidRuntime (tunable).

- `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureStepHandler.kt`  
  Uses Allure.lifecycle.addAttachment(name, InputStream/ByteArray, type, ext) with correct signature/order.

## iOS configuration (allure-xcresult)
- Tool: https://github.com/kvld/allure-xcresult  
- We installed the converter binary: `AllureXCResult`  
- Symlinked `allure-xcresult`  
- The run script supports multiple ways to invoke it:
  ```bash
  ALLURE_XCRESULT_BIN=/usr/local/bin/AllureXCResult
  ALLURE_XCRESULT_REPO=/Users/.../Documents/Repos/allure-xcresult   # uses: swift run -c release AllureXCResult
  ```
- Simulator APNs caveat:  
  On iOS simulator, Push/APNs token isn’t available; code calling `FirebaseMessaging.getToken()` will fail.  
  To run UI tests on simulator, guard/disable push initialization or use a physical device with proper entitlements.

## Run script and environment
Script: `integration_test/run_patrol_allure.sh`

**Capabilities:**
- Single test (pass a file)
- All tests (pass the `integration_test` directory or no args)
- Tag filtering (Patrol’s `--tags` and `--exclude-tags`)
- Platform detection: Android/iOS/auto
- Android: pulls `allure-results` from device TestStorage
- iOS: converts latest `.xcresult` to Allure results via allure-xcresult
- Writes `environment.properties` and `categories.json` to the run dir
- Preserves `history/` for trends before generation
- Generates clean report and serves it locally

**Environment file (auto-sourced)**  
`integration_test/patrol_env.sh` (auto-loaded by the script if present)  
Edit once; it exports:
```
APP_VERSION, FLAVOR, APP_ENV, BASE_URL, GIT_SHA
PATROL_CONFIG_JSON, FEATURE_FLAGS_TEXT
PLATFORM (android|ios|auto)
TAGS, EXCLUDE_TAGS
ALLURE_XCRESULT_BIN or ALLURE_XCRESULT_REPO (optional)
```
You can also export or inline env vars without using the file.

### Schemathesis integration

Schemathesis is integrated into the same flow via two scripts:

- `integration_test/run_schemathesis.sh` – wrapper around `schemathesis run`.
- `integration_test/run_patrol_allure.sh` – can start the Schemathesis wrapper in
  parallel and import its results as a single synthetic test.

Key env toggles (all optional):

- `RUN_ST` – `1` (default) to start Schemathesis in background; `0` to disable.
- `SCHEMATHESIS_WRAPPER` – path to wrapper (default:
  `./integration_test/run_schemathesis.sh`).
- `ST_URL` – base API URL for Schemathesis (required when `RUN_ST=1`).
- `ST_SCHEMA` – schema path (default `openapi-docs.yaml`).
- `ST_DIR` – Schemathesis report dir (default `integration_test/schemathesis-report/`).
- `ST_WAIT_TOKEN_SECS` – how long the wrapper waits for
  `.schemathesis_token` inside the app sandbox.
- `ST_PULL_TOKEN_TIMEOUT_SECS` – how long this script keeps trying to pull the
  token file from device/simulator to host.
- `ST_FINISH_TIMEOUT_SECS` – optional host-side timeout for waiting until
  Schemathesis finishes before importing results (0 = do not wait).

Flow (high level):

1. **Token export** – Patrol tests log in with `EXPORT_TOKEN=1`; the app writes
   the Cognito access token into `.schemathesis_token` in its sandbox.
2. **Token puller** – `run_patrol_allure.sh` runs a background job that copies
   `.schemathesis_token` to the host root of the repo:
   - Android: `adb exec-out run-as <pkg> cat app_flutter/.schemathesis_token`.
   - iOS Simulator: `integration_test/ios_pull_token.sh` + `xcrun simctl`.
3. **Schemathesis run** – if `RUN_ST=1` and `ST_URL` is set, the script starts
   `run_schemathesis.sh` in the background, which:
   - Uses `./integration_test/myenv/bin/schemathesis` by default.
   - Reads `.schemathesis_token` and injects
     `Authorization: Bearer <token>` (unless `AUTH_HEADER` is already set).
   - Writes JUnit + HAR into `integration_test/schemathesis-report/`.
4. **Import into Allure** – after Patrol results are present, the script:
   - Waits up to `ST_FINISH_TIMEOUT_SECS` for Schemathesis to complete (if > 0).
   - Takes the latest `junit-*.xml` and `har-*.json` from `integration_test/schemathesis-report/`.
   - Generates summaries (`.txt`, `.html`, `.json`) and redacts
     `Authorization: Bearer ...` in HAR.
   - Creates **one** synthetic test result JSON:
     - Suite: `Schemathesis`.
     - Name: `Schemathesis contract`.
     - Attachments: JUnit XML (as attachment-only), summary, HAR (redacted),
       console output.
   - Removes any other Schemathesis-origin tests so that only this aggregated
     test appears in Allure.

Typical command for this repo:

```bash
ST_URL="https://jsxhc7emf3.execute-api.eu-west-1.amazonaws.com" \
TAGS=regression EXPORT_TOKEN=1 RUN_ST=1 \
ST_FINISH_TIMEOUT_SECS=120 \
./integration_test/run_patrol_allure.sh
```

Resulting Allure suites (iOS example):

- `RunnerUITests` – Patrol UI tests.
- `Schemathesis` – single aggregated test `Schemathesis contract` with
  JUnit/HAR/summary attached.

## Running tests

### Single test (Android/iOS auto-detect)
```bash
./integration_test/run_patrol_allure.sh integration_test/cardCanBeFrozenOrUnfreeze_test.dart
```

### All tests (Android/iOS auto-detect)
```bash
./integration_test/run_patrol_allure.sh
# or
./integration_test/run_patrol_allure.sh integration_test
```

### By tags (Patrol supports complex tag expressions)
Add tags to tests: `patrolTest('...', tags: ['smoke'])`

Run with tags:
```bash
TAGS="smoke" ./integration_test/run_patrol_allure.sh
TAGS="smoke||regression" ./integration_test/run_patrol_allure.sh
TAGS="(login && smoke)" ./integration_test/run_patrol_allure.sh
```

Exclude:
```bash
EXCLUDE_TAGS="regression" ./integration_test/run_patrol_allure.sh
```

### Force platform usage
```bash
PLATFORM=android ./integration_test/run_patrol_allure.sh   # Android only
PLATFORM=ios ./integration_test/run_patrol_allure.sh       # iOS only
```

### iOS conversion (if needed explicitly)
```bash
ALLURE_XCRESULT_BIN=/usr/local/bin/AllureXCResult PLATFORM=ios ./integration_test/run_patrol_allure.sh
```

## What gets captured

### Android (by rules and harness code)
- End-of-test screenshot (always)
- Window hierarchy snapshot
- Filtered logcat on failures (PID/tag/level based)
- Custom attachments (optional, via env)
- Error details (text) when failures are handled in the step handler

### iOS
- All test results and attachments that exist inside the `.xcresult` bundle are converted into Allure artifacts by allure-xcresult.

## Categories
A default `categories.json` is written into each run dir:
- App crashes
- UI not found
- Network/timeout

Adjust this file if you want different bucketing.

## Failures in Allure
- Android and iOS: results are always pulled from TestStorage; failed tests are present with their artifacts.

## Trends and history
The script copies `build/allure-report/history` into each `per-run build/reports/allure-results/<timestamp>/` before generation.  
This enables trend graphs (flaky/regressions) across runs.

## Tags and filtering (Patrol)
Define tags in tests with `tags: ['smoke', 'regression']`.

Filter with:
```bash
--tags smoke
--tags 'smoke||regression'
--tags '(login && smoke)'
```

Exclude with:
```bash
--exclude-tags regression
```

The run script forwards `TAGS` and `EXCLUDE_TAGS` env vars to Patrol CLI.

## Useful commands

### Run (single)
```bash
./integration_test/run_patrol_allure.sh integration_test/<test>.dart
```

### Run (all)
```bash
./integration_test/run_patrol_allure.sh
```

### Android manual pull (if needed)
```bash
adb exec-out sh -c 'cd /sdcard/googletest/test_outputfiles && tar cf - allure-results' | tar xvf - -C build/reports
```

### Allure generate
```bash
allure generate -c -o build/allure-report build/reports/allure-results
```

### Allure serve
```bash
allure serve build/reports/allure-results
```

### iOS converter version
```bash
AllureXCResult --version
# or
allure-xcresult --version
```

## Environment metadata
Automatically written to each run’s `environment.properties`:
```
appVersion, flavor, device, apiLevel, gitSha, baseUrl
```
Source:
- `APP_VERSION, FLAVOR, APP_ENV, BASE_URL, GIT_SHA` from environment or env file
- On Android, `device` and `apiLevel` default from adb if not provided
- On iOS, provide `DEVICE_NAME` and `OS` via env (recommended) if you want precise info

## Logcats
`FilteredLogcatRule` attaches logcat on failure only, reducing noise by:
- Trying PID-filtered logcat first
- Falling back to tag-based filter with a minimum level
You can tune tags/level in `FilteredLogcatRule` constructor.

## Notes and pitfalls

- Allure attachment API: Use `Allure.lifecycle.addAttachment(name, stream/body, type, ext)` with correct parameter order.
- Allure links API: Use two-argument: `Allure.link("commit", sha)`
- iOS APNs on Simulator: The simulator does not provide an APNs token; guard push init or run on a device with proper entitlements.
- Patrol steps: Step-level reporting in Allure typically requires extra wrapping/instrumentation. Those wrappers are not included here.

## Optional enhancements
- Per-test severity/owner from tags: Map Patrol tags to Allure labels (via the Android harness) if desired.

## Summary
- Android and iOS Allure reporting is wired.
- Use `integration_test/run_patrol_allure.sh` to run single/all/tagged tests, collect results, write metadata, preserve history, and generate/serve reports.
- Failures are included and categorized; screenshots/logs/hierarchies are attached.
- Environment variables control the report’s Environment panel and optional attachments.
- iOS conversion is handled by allure-xcresult.
