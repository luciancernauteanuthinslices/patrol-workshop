# Firebase Test Lab - Test Artifacts Ready

## Build Status: ✅ COMPLETE

Both iOS and Android test bundles have been successfully built for Firebase Test Lab.

## iOS Test Artifacts

**Location:** `build/ios_integ/Build/Products/Release-dev-iphoneos/`

- **App under test:** `Runner.app`
- **Test instrumentation app:** `RunnerUITests-Runner.app`
- **XCTest run file:** `build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun`

**Upload to Firebase Test Lab:**
```bash
gcloud firebase test ios run \
  --type xctest \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=ios_tests_$(date +%Y%m%d_%H%M%S)
```

## Android Test Artifacts

**Location:** `build/app/outputs/apk/debug/`

- **App under test:** `app-debug.apk`
- **Test instrumentation app:** `build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`

**Upload to Firebase Test Lab:**
```bash
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --device model=Pixel4,version=30 \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=android_tests_$(date +%Y%m%d_%H%M%S)
```

## Prerequisites for Upload

1. **Google Cloud SDK installed:**
   ```bash
   gcloud --version
   ```

2. **Authenticated with Google Cloud:**
   ```bash
   gcloud auth login
   gcloud config set project YOUR_GCP_PROJECT_ID
   ```

3. **Firebase Test Lab API enabled:**
   ```bash
   gcloud services enable testing.googleapis.com
   ```

4. **GCS bucket for test results:**
   - Create a bucket or use existing: `gs://YOUR_TEST_RESULTS_BUCKET`

## Test Configuration

### iOS
- **Flavor:** dev
- **Build Type:** Release
- **Minimum iOS:** 14.0
- **Test Runner:** XCTest

### Android
- **Build Type:** Debug (compatible with Patrol)
- **Minimum SDK:** 21
- **Target SDK:** 34
- **Test Runner:** PatrolJUnitRunner

## Next Steps

1. Set your GCP project ID and test results bucket
2. Run the appropriate upload command for iOS or Android
3. Monitor test progress in Firebase Console
4. View results and logs after completion

## Notes

- Android tests use debug build type due to Patrol CLI compatibility with product flavors
- iOS tests use dev flavor as specified in pubspec.yaml
- Both builds have code signing disabled for FTL compatibility
- Test results will be stored in your GCS bucket for 30 days

---

**Generated:** October 29, 2025
**Test Framework:** Patrol 3.19.0
**Flutter Version:** 3.16.0+
