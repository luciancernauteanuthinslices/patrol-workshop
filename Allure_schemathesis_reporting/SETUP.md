# Allure + Schemathesis Integration Package

> Drop-in package for integrating Patrol (Flutter), Allure, and Schemathesis into another project.
>
> This folder contains **copies** of the key helpers and scripts. Adjust package names, bundle IDs, and URLs for your app.

---

## 1. Files included

### Dart helper

- `lib/testing/token_export.dart`
  - Exports a JWT access token from your app to `.schemathesis_token` when built with `--dart-define=EXPORT_TOKEN=true`.

### Android test helpers

- `android/app/src/androidTest/resources/allure.properties`
  - Enables TestStorage-based Allure results:
    ```properties
    allure.results.useTestStorage=true
    ```
- `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureEnrichmentRule.kt`
- `android/app/src/androidTest/java/com/thinslices/solarisdemo/FilteredLogcatRule.kt`
- `android/app/src/androidTest/java/com/thinslices/solarisdemo/AllureStepHandler.kt`

> **Important**: Update the package name (`com.thinslices.solarisdemo`) to match your project.

### Integration scripts

- `integration_test/allure_schemathesis_reporting/run_patrol_allure.sh`
- `integration_test/allure_schemathesis_reporting/run_schemathesis.sh`
- `integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh`
- `integration_test/allure_schemathesis_reporting/st_aggregate_to_allure.py`
- `integration_test/allure_schemathesis_reporting/patrol_env.sh`
- `integration_test/allure_schemathesis_reporting/sct_auth/get_schemathesis_token.sh`
- `integration_test/allure_schemathesis_reporting/sct_auth/ios_pull_token.sh`
- `integration_test/allure_schemathesis_reporting/schemathesis_severity.json` (template)

> The `run_patrol_allure.sh` here is the **full script** from the source repo, with all Schemathesis integration and reporting logic included. You typically only need to adjust environment variables (e.g. `BASE_URL`, `ST_URL`, `PKG`, `BUNDLE_ID`) and, if desired, trim options you don't use.

---

## 2. Gradle changes (Android)

In your **app module** `android/app/build.gradle`:

1. **Instrumentation runner**

   ```groovy
   android {
       defaultConfig {
           testInstrumentationRunner "com.thinslices.solarisdemo.AllurePatrolJUnitRunner"
       }
   }
   ```

   - If your package is different, change `com.thinslices.solarisdemo` accordingly.

2. **Allure dependencies (androidTest)**

   ```groovy
   dependencies {
       androidTestImplementation "io.qameta.allure:allure-kotlin-model:2.4.0"
       androidTestImplementation "io.qameta.allure:allure-kotlin-commons:2.4.0"
       androidTestImplementation "io.qameta.allure:allure-kotlin-junit4:2.4.0"
       androidTestImplementation "io.qameta.allure:allure-kotlin-android:2.4.0"

       androidTestImplementation "androidx.test.uiautomator:uiautomator:2.2.0"
       androidTestUtil "androidx.test:orchestrator:1.5.1" // optional but recommended
   }
   ```

3. Ensure `allure.properties` is placed under:

   ```
   android/app/src/androidTest/resources/allure.properties
   ```

---

## 3. Flutter / Dart changes

In `pubspec.yaml` add (if not present):

```yaml
dependencies:
  path_provider: ^2.1.0  # or compatible version
```

Then add the helper file:

- Copy `lib/testing/token_export.dart` into your project.
- Wire it into your auth flow after a successful login, e.g.:

  ```dart
  import 'package:your_app/testing/token_export.dart';

  // After you obtain the access token
  if (kExportForSchemathesis) {
    await TokenExport.save(accessToken);
  }
  ```

Build tests with:

```bash
patrol test --dart-define=EXPORT_TOKEN=true ...
```

---

## 4. Tool installation (Allure, Schemathesis, Patrol)

Install these tools locally (and/or in CI) before using the scripts.

### 4.1 Allure CLI

Allure requires Java 8+ on the system.

- **macOS (Homebrew)**

  ```bash
  brew install qameta/allure/allure
  ```

- **Manual (any OS with Java)**

  1. Download the latest Allure commandline zip from: https://github.com/allure-framework/allure2/releases
  2. Unzip it to a stable location, e.g. `/opt/allure`.
  3. Add the `bin` folder to `PATH`, e.g. on macOS/Linux:

     ```bash
     export PATH="/opt/allure/bin:$PATH"
     ```

- **Verify**

  ```bash
  allure --version
  ```

### 4.2 Schemathesis

You can either install Schemathesis **globally** or let the scripts manage a **project-local venv**.

- **Global install (simple for local usage)**

  ```bash
  pip install --upgrade schemathesis
  # or, if you prefer pipx:
  # pipx install schemathesis
  ```

- **Project venv (matches the scripts’ default)**

  The scripts default to:

  ```text
  integration_test/allure_schemathesis_reporting/myenv/bin/schemathesis
  ```

  To create it manually:

  ```bash
  python3 -m venv integration_test/allure_schemathesis_reporting/myenv
  integration_test/allure_schemathesis_reporting/myenv/bin/pip install --upgrade pip
  integration_test/allure_schemathesis_reporting/myenv/bin/pip install schemathesis
  ```

  Or let the scripts do this automatically by setting:

  ```bash
  AUTO_VENV=1 ./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
  ```

### 4.3 Patrol CLI

Install the Patrol CLI globally with `dart pub`:

```bash
dart pub global activate patrol_cli
```

Ensure `~/.pub-cache/bin` (or the equivalent on your OS) is on your `PATH` so `patrol` is available:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
```

Verify:

```bash
patrol --help
```

### 4.4 Optional: allure-xcresult (iOS converter)

Only needed if you run Patrol + Allure on **iOS** and want to convert `.xcresult` bundles into Allure results.

```bash
git clone https://github.com/kvld/allure-xcresult.git
cd allure-xcresult
swift build -c release

# Optionally expose the binary on PATH as `allure-xcresult`
ln -s "$(pwd)/.build/release/AllureXCResult" /usr/local/bin/allure-xcresult
```

Then either:

- Let `run_patrol_allure.sh` find `allure-xcresult` on `PATH`, or
- Point it directly at the built binary via:

  ```bash
  ALLURE_XCRESULT_BIN=/usr/local/bin/allure-xcresult
  ```

---

## 5. Basic usage

### Patrol + Allure only

```bash
PLATFORM=android RUN_ST=0 SERVE_REPORT=1 \
  ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh integration_test
```

### Patrol + token export + Schemathesis (export_token mode)

1. Patrol login + token export:

   ```bash
   PLATFORM=android EXPORT_TOKEN=1 RUN_ST=0 IMPORT_ST_INTO_PATROL=0 SERVE_REPORT=0 \
     ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh integration_test/login_test.dart
   ```

2. Schemathesis + Allure:

   ```bash
   AUTO_VENV=1 GET_TOKEN_MODE=export_token ST_URL="https://your-api.example.com" \
     ./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
   ```

3. Patrol again to attach deeplink:

   ```bash
   PLATFORM=android RUN_ST=0 IMPORT_ST_INTO_PATROL=1 SERVE_REPORT=0 \
     ./integration_test/allure_schemathesis_reporting/run_patrol_allure.sh integration_test/login_test.dart
   ```

---

## 6. Schemathesis direct_api mode

Instead of pulling tokens from the device, you can obtain them via OAuth2:

```bash
AUTO_VENV=1 GET_TOKEN_MODE=direct_api \
ST_URL="https://your-api.example.com" \
ST_AUTH_URL="https://your-auth.example.com/oauth2/token" \
ST_AUTH_CLIENT_ID="your-client-id" \
ST_AUTH_CLIENT_SECRET="..." \  # if your auth script expects it
ST_AUTH_USERNAME="..." \       # for password grant, if used
ST_AUTH_PASSWORD="..." \       # for password grant, if used
./integration_test/allure_schemathesis_reporting/run_schemathesis_allure.sh
```

See `integration_test/allure_schemathesis_reporting/sct_auth/get_schemathesis_token.sh` for details.

---

## 7. Git ignore suggestions

In your new project, ignore:

```gitignore
/integration_test/allure_schemathesis_reporting/myenv/
/integration_test/schemathesis-report/
/build/allure-report/
/build/allure-report-schemathesis/
/build/schemathesis-allure/
.schemathesis_token
```

These keep venvs, local reports, and tokens out of version control.

---

This package is a starting point; adapt paths, package names, and URLs to fit your project structure.
