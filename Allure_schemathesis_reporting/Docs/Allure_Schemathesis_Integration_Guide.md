# Allure + Schemathesis Integration Guide

> **Audience**: QA Engineers setting up Patrol E2E tests with Allure and Schemathesis API contract tests.

> **Scope**: How to configure, run, and tune Allure, Schemathesis, and their integration (including token export) in this repo or a new project.

---

## 1. Folder layout & key files

In this project the integration lives under:

- `lib/testing/token_export.dart`
  - App-side helper that writes a JWT access token into the app sandbox when `--dart-define=EXPORT_TOKEN=true`.
- `integration_test/allure_schemathesis_reporting/`
  - `run_patrol_allure.sh` – Patrol + Allure runner (Android & iOS) with optional Schemathesis import and deeplink.
  - `run_schemathesis.sh` – Wrapper around `schemathesis run` (JUnit + HAR only).
  - `run_schemathesis_allure.sh` – Full Schemathesis + Allure pipeline (separate Allure report).
  - `st_aggregate_to_allure.py` – Converts Schemathesis JUnit + HAR into Allure results (1 test per endpoint + API health check).
  - `patrol_env.sh` – Optional env file auto-sourced by `run_patrol_allure.sh`.
  - `sct_auth/get_schemathesis_token.sh` – Device‑independent token fetch from auth API (direct OAuth2).
  - `sct_auth/ios_pull_token.sh` – Helper to pull `.schemathesis_token` from iOS Simulator.
  - `schemathesis_severity.json` – Per‑endpoint risk mapping (critical/normal/low).

When porting to a new project, keep the same structure, but update:

- Package / bundle IDs (`PKG`, `BUNDLE_ID`).
- API base URL (`ST_URL`, `BASE_URL`).
- OpenAPI schema path (`ST_SCHEMA`, usually `openapi-docs.yaml`).
- Severity config (`schemathesis_severity.json`) according to that project’s risk model.

---

## 2. Prerequisites

- **CLI tools**
  - Patrol CLI installed & on PATH.
  - Allure CLI installed & on PATH (`allure --version`).
  - Python 3 available.
- **Mobile tooling**
  - Android: emulator or device available via `adb`.
  - iOS: Xcode + Command Line Tools for `xcrun simctl` (if running on iOS simulator).
- **Flutter app changes**
  - `lib/testing/token_export.dart` included.
  - Auth flow wired to call `TokenExport.save()` after a successful login (see `docs/Schemathesis_Token_Export.md`).

---

## 3. Token export & authentication

### 3.1. App‑side export

- Compile‑time flag:
  - `--dart-define=EXPORT_TOKEN=true` (or env `EXPORT_TOKEN=1` when using `run_patrol_allure.sh`).
- Behavior:
  - After a successful login, the app writes the access token to `.schemathesis_token` in its sandbox.
  - Path examples:
    - Android: `/data/data/<PKG>/app_flutter/.schemathesis_token`.
    - iOS Simulator: `<AppContainer>/Documents/.schemathesis_token`.

### 3.2. Host‑side token

Two ways to obtain the token for Schemathesis:

- **Mode 1 – `export_token` (from device)**
  - Patrol test + app export token into sandbox.
  - Scripts pull it to host as `./.schemathesis_token`.
  - Used when `GET_TOKEN_MODE=export_token`.

- **Mode 2 – `direct_api` (device‑independent)**
  - `sct_auth/get_schemathesis_token.sh` calls your auth API (OAuth2) and prints a token.
  - Used when `GET_TOKEN_MODE=direct_api`.

Both `run_patrol_allure.sh` and `run_schemathesis_allure.sh` understand these modes.

---

## 4. Allure + Patrol (UI tests only)

Main script: `integration_test/allure_schemathesis_reporting/run_patrol_allure.sh`

### 4.1. Important env vars

- **Core**
  - `TARGET` – Test file or directory (default: `integration_test`).
  - `PLATFORM` – `android`, `ios`, or `auto` (default: `auto`).
  - `TAGS`, `EXCLUDE_TAGS` – Patrol tag filters.
  - `SERVE_REPORT` – `1` to run `allure serve`, `0` for static HTML only.

- **Environment panel** (can be set in `patrol_env.sh` or env):
  - `APP_VERSION`, `FLAVOR`, `APP_ENV`, `BASE_URL`, `GIT_SHA`.
  - `DEVICE_NAME`, `API_LEVEL` (iOS recommended, Android auto‑detected if missing).

### 4.2. Running Patrol + Allure (no Schemathesis)

- Single test:
  ```bash
  ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh \
    integration_test/logIn_test.dart
  ```

- All tests in `integration_test/`:
  ```bash
  ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh
  ```

 Result:

- Allure results: `build/reports/allure-results/<timestamp>*/`.
- HTML report: `build/allure-report/index.html`.

 For CI, archive `build/allure-report` as an artifact.

### 4.3. Android configuration (project setup)

 To make Allure work with Patrol on Android, ensure the following project configuration (see also `docs/Allure_Reporting_Guide.md`):

 - **Instrumentation runner** in `android/app/build.gradle`:
   ```groovy
   testInstrumentationRunner = "com.thinslices.solarisdemo.AllurePatrolJUnitRunner"
   ```

 - **Allure dependencies** (androidTest):
   ```groovy
   androidTestImplementation "io.qameta.allure:allure-kotlin-model:2.4.0"
   androidTestImplementation "io.qameta.allure:allure-kotlin-commons:2.4.0"
   androidTestImplementation "io.qameta.allure:allure-kotlin-junit4:2.4.0"
   androidTestImplementation "io.qameta.allure:allure-kotlin-android:2.4.0"
   ```

 - **UiAutomator** (pinned to satisfy transitive versions):
   ```groovy
   androidTestImplementation "androidx.test.uiautomator:uiautomator:2.2.0"
   ```

 - **Orchestrator** (optional but recommended):
   ```groovy
   androidTestUtil "androidx.test:orchestrator:1.5.1"
   ```

 - **Allure properties** to enable TestStorage:
   - Create `android/app/src/androidTest/resources/allure.properties`:
     ```properties
     allure.results.useTestStorage=true
     ```

 - **Android helper code (key files)**:
   - `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureEnrichmentRule.kt`
     - Sets labels (e.g., `suite=Patrol`, `feature=Mobile E2E`, `severity=critical`, `owner=QA Team`).
     - Adds links from env vars (e.g., `GIT_SHA`, `TMS_ID`).
     - Adds parameters: device, API level, flavor, env (from environment variables).
   - `android/app/src/androidTest/java/com/thinslices/solarisdemo/FilteredLogcatRule.kt`
     - Clears logcat before each test; on failure attaches filtered logcat.
   - `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureStepHandler.kt`
     - Wraps Allure attachments using `Allure.lifecycle.addAttachment(...)` with the correct signature.

 These pieces are responsible for the rich Android artifacts you see in the Allure report (screenshots, logcat, labels, links).

### 4.4. iOS configuration (allure-xcresult)

 For iOS, Allure integration is based on converting the `.xcresult` bundle produced by Xcode / Patrol into Allure results using `allure-xcresult`:

 - Tool repo: https://github.com/kvld/allure-xcresult  
 - Typical setup in this repo:
   - Built the converter binary: `AllureXCResult`.
   - Symlinked `allure-xcresult`.
   - The run script supports multiple ways to invoke it, for example:
     ```bash
     ALLURE_XCRESULT_BIN=/usr/local/bin/AllureXCResult
     ALLURE_XCRESULT_REPO=/Users/.../Documents/Repos/allure-xcresult   # uses: swift run -c release AllureXCResult
     ```

 - In general, install or build the converter (e.g. `AllureXCResult`) and expose it as either:
   - A direct binary via `ALLURE_XCRESULT_BIN=/usr/local/bin/AllureXCResult`, or
   - A cloned repo via `ALLURE_XCRESULT_REPO=/path/to/allure-xcresult` (used with `swift run -c release AllureXCResult`).

 - `run_patrol_allure.sh` will then:
   - Locate the latest `.xcresult` under `./build`.
   - Call the converter to generate Allure results into the current run directory.
   - Populate iOS device information (simulator name, OS version) into the Allure Environment panel when possible.

 This configuration, together with `run_patrol_allure.sh`, is enough to produce Allure reports for Patrol tests on iOS.

---

## 5. Schemathesis as a standalone tool

Two options:

1. **Raw CLI via `run_schemathesis.sh`** – runs Schemathesis and writes JUnit + HAR.
2. **Full Allure pipeline via `run_schemathesis_allure.sh`** – recommended.

### 5.1. `run_schemathesis_allure.sh` (recommended)

Script: `integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh`

Key env vars:

- **Core**
  - `ST_URL` – API base URL (required).
  - `ST_SCHEMA` – OpenAPI schema path (default: `openapi-docs.yaml`).
  - `SCHEMATHESIS_BIN` – Optional path to `schemathesis` binary.
  - `AUTO_VENV` – `1` to auto‑create venv & install Schemathesis under `integration_test/allure_schemathesis_reporting/myenv`.

- **Generation controls**
  - `ST_PHASES` – comma list of valid phases (default: `examples,coverage,stateful`).
  - `ST_MODE` – `all` or `positive` (default: `all`).
  - `ST_WORKERS` – concurrency (`5` by default).
  - `ST_WEIGHT` – `auto` or explicit workers weight (`auto` by default).

- **Auth modes**
  - `GET_TOKEN_MODE` – `export_token` (default) or `direct_api`.
  - `PKG`, `BUNDLE_ID` – app identifiers for token pulling.
  - `AUTH_SCRIPT` – path to direct API auth script (default: `sct_auth/get_schemathesis_token.sh`).
  - When `GET_TOKEN_MODE=direct_api`, the auth script reads its configuration from env vars such as:
    - `ST_AUTH_URL`, `ST_AUTH_CLIENT_ID`, `ST_AUTH_CLIENT_SECRET`
    - `ST_AUTH_USERNAME`, `ST_AUTH_PASSWORD` (for password grant, if used)
    - These have **no defaults**; set them via your shell or CI secrets. See `sct_auth/get_schemathesis_token.sh` for details.

Outputs:

- Raw Schemathesis run: `build/schemathesis-allure/run/` (JUnit + HAR + `output.txt`).
- Allure results: `build/schemathesis-allure/allure-results/`.
- HTML report: `build/allure-report-schemathesis/`.
- Global health summary JSON: `build/schemathesis-allure/allure-results/schemathesis_summary.json`.

Example – token from device (already exported via Patrol):

```bash
AUTO_VENV=1 \
GET_TOKEN_MODE=export_token \
ST_URL="https://your-api.example.com" \
./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
```

Example – token via auth API (`GET_TOKEN_MODE=direct_api`):

```bash
AUTO_VENV=1 \
GET_TOKEN_MODE=direct_api \
ST_URL="https://your-api.example.com" \
ST_AUTH_URL="https://your-auth.example.com/oauth2/token" \
ST_AUTH_CLIENT_ID="your-client-id" \
ST_AUTH_CLIENT_SECRET="..." \  # if your auth script expects it
ST_AUTH_USERNAME="..." \       # for password grant, if used
ST_AUTH_PASSWORD="..." \       # for password grant, if used
./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
```

To tune coverage vs speed:

- More examples / fuzzing:
  - `ST_PHASES="examples,coverage,fuzzing,stateful"`
  - `ST_MODE="all"` and `ST_WORKERS=8` (if your backend can handle it).
- Quieter, fast sanity check:
  - `ST_MODE="positive"`
  - `ST_PHASES="examples,coverage"`.

---

## 6. Combined flow: Patrol + Schemathesis + Allure deeplink

Goal: generate **two** reports and a link from Patrol → Schemathesis.

1. **Login & export token via Patrol** (no Schemathesis yet):

   ```bash
   PLATFORM=android \
   EXPORT_TOKEN=1 \
   RUN_ST=0 \
   IMPORT_ST_INTO_PATROL=0 \
   SERVE_REPORT=0 \
   ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh \
     integration_test/logIn_test.dart
   ```

2. **Run Schemathesis + Allure** using that token:

   ```bash
   AUTO_VENV=1 \
   GET_TOKEN_MODE=export_token \
   ST_URL="https://your-api.example.com" \
   ./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
   ```

   Or, if you prefer device‑independent auth, use `GET_TOKEN_MODE=direct_api` and provide the auth env vars:

   ```bash
   AUTO_VENV=1 \
   GET_TOKEN_MODE=direct_api \
   ST_URL="https://your-api.example.com" \
   ST_AUTH_URL="https://your-auth.example.com/oauth2/token" \
   ST_AUTH_CLIENT_ID="your-client-id" \
   ST_AUTH_CLIENT_SECRET="..." \  # if your auth script expects it
   ST_AUTH_USERNAME="..." \       # for password grant, if used
   ST_AUTH_PASSWORD="..." \       # for password grant, if used
   ./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
   ```

3. **Run Patrol again to refresh the E2E report and attach the Schemathesis deeplink**:

   ```bash
   PLATFORM=android \
   RUN_ST=0 \
   IMPORT_ST_INTO_PATROL=1 \
   SERVE_REPORT=0 \
   ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh \
     integration_test/logIn_test.dart
   ```

After step 3 you’ll have:

- Patrol Allure report: `build/allure-report/index.html`.
- Schemathesis Allure report: `build/allure-report/schemathesis/index.html`.
- Deeplink from the Patrol report to the Schemathesis report via Allure’s **Executor** panel.

For CI, upload `build/allure-report` as a job artifact; opening `index.html` locally will keep the deeplink working.

---

## 7. Using each piece independently

- **Allure only (UI tests)**
  - Use `run_patrol_allure.sh` with `RUN_ST=0` and ignore Schemathesis env vars.

- **Schemathesis only**
  - Use `run_schemathesis_allure.sh` directly (no Patrol needed) and set `GET_TOKEN_MODE` as appropriate.

- **No‑auth APIs**
  - Use `GET_TOKEN_MODE=export_token` but simply do not export a token, or extend the scripts with a `GET_TOKEN_MODE=none` branch if you want fully unauthenticated runs. In that case, Schemathesis will run without the `Authorization` header.

---

## 8. Git ignore (recommended)

When you port this setup to another project, you generally **do not** want to commit:

- Local Python virtual env used for Schemathesis:
  - `integration_test/allure_schemathesis_reporting/myenv/`

- Schemathesis raw output directories:
  - `integration_test/schemathesis-report/`
  - `build/schemathesis-allure/` (run + Allure results)

- Allure generated reports:
  - `build/allure-report/`
  - `build/allure-report-schemathesis/`

- Sensitive token file:
  - `.schemathesis_token`

These rules are recommended for any new project so your Git history stays clean and free of local reports or secrets.

This guide should be enough for a new engineer to understand how to configure, run, and tune the Allure + Schemathesis combo in this repo or a similar project.
