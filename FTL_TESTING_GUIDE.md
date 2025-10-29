# Firebase Test Lab Testing Guide

This guide explains how to test your iOS builds on Firebase Test Lab after successfully building them with Patrol.

## Prerequisites

- Google Cloud Platform (GCP) project with Firebase Test Lab API enabled
- Firebase project linked to your GCP project
- Firebase CLI installed (`npm install -g firebase-tools`)
- Google Cloud SDK installed (`gcloud` CLI)
- Successfully built iOS test bundle from the FTL Build Guide

## Setup Instructions

### 1. Install Required Tools

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Install Google Cloud SDK
# Follow instructions at: https://cloud.google.com/sdk/docs/install

# Verify installation
firebase --version
gcloud --version
```

### 2. Authenticate with Google Cloud

```bash
# Login to Google Cloud
gcloud auth login

# Set your active project
gcloud config set project YOUR_GCP_PROJECT_ID

# Enable Firebase Test Lab API (if not already enabled)
gcloud services enable testing.googleapis.com
```

### 3. Link Firebase Project

```bash
# Link your Firebase project to the local directory
firebase use YOUR_FIREBASE_PROJECT_ID

# Or login with Firebase
firebase login
```

## Testing Methods

### Method 1: Using gcloud CLI (Recommended)

#### Upload and Run Tests

```bash
# Basic test execution
gcloud firebase test ios run \
  --type xctest \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=TEST_RUN_ID

# Advanced test execution with device specifications
gcloud firebase test ios run \
  --type xctest \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5,orientation=portrait \
  --device model=iphone15,version=17.0,orientation=landscape \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=TEST_RUN_ID \
  --timeout=20m \
  --environment-variables="CLEAR_APP_DATA=true"

# Test with retry attempts (retry failed tests up to 2 times)
gcloud firebase test ios run \
  --type xctest \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=TEST_RUN_ID \
  --test-num-flaky-test-attempts=2
```

#### Common Device Options

```bash
# iPhone 14 (iOS 16.5)
--device model=iphone14,version=16.5

# iPhone 15 (iOS 17.0)  
--device model=iphone15,version=17.0

# iPad (iOS 16.5)
--device model=ipad9,version=16.5

# Multiple orientations
--device model=iphone14,version=16.5,orientation=portrait
--device model=iphone14,version=16.5,orientation=landscape
```

### Method 2: Using Firebase Console

1. **Navigate to Firebase Console**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Go to "Quality" → "Firebase Test Lab"

2. **Upload Test Bundle**
   - Click "Run your first test"
   - Select "iOS" as the platform
   - Upload your `.xctestrun` file
   - The app files will be automatically included

3. **Configure Test**
   - Choose device(s) to test on
   - Set test duration and options
   - Click "Start tests"

### Method 3: Using Firebase CLI

```bash
# Upload and run via Firebase CLI
firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5
```

## Android Testing

### Upload and Run Android Tests

```bash
# Basic Android test execution
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/release/app-release-androidTest.apk \
  --app build/app/outputs/apk/release/app-release.apk \
  --device model=Pixel4,version=30 \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=TEST_RUN_ID

# Android test with retry attempts (retry failed tests up to 2 times)
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/release/app-release-androidTest.apk \
  --app build/app/outputs/apk/release/app-release.apk \
  --device model=Pixel4,version=30 \
  --device model=Pixel6,version=33 \
  --results-bucket=gs://YOUR_TEST_RESULTS_BUCKET \
  --results-dir=TEST_RUN_ID \
  --test-num-flaky-test-attempts=2 \
  --timeout=20m \
  --environment-variables="CLEAR_APP_DATA=true"
```

### Common Android Device Options

```bash
# Pixel 4 (Android 11)
--device model=Pixel4,version=30

# Pixel 6 (Android 13)
--device model=Pixel6,version=33

# Samsung Galaxy S21 (Android 12)
--device model=galaxys21,version=31

# Multiple Android versions
--device model=Pixel4,version=30
--device model=Pixel4,version=31
--device model=Pixel6,version=33
```

## Test Configuration Options

### Device Specifications

#### iOS Devices

| Model | Version | Orientation | Notes |
|-------|---------|-------------|-------|
| iphone14 | 16.5, 17.0 | portrait, landscape | Latest iPhone models |
| iphone15 | 17.0 | portrait, landscape | Newest iPhone with A17 chip |
| ipad9 | 16.5, 17.0 | portrait, landscape | 10.9-inch iPad |
| ipadmini6 | 16.5, 17.0 | portrait, landscape | 8.3-inch iPad mini |

#### Android Devices

| Model | Version | Notes |
|-------|---------|-------|
| Pixel4 | 30, 31, 32 | Android 11-13, good baseline device |
| Pixel6 | 33, 34 | Android 13-14, latest Pixel |
| Pixel7 | 33, 34 | Android 13-14, premium device |
| galaxys21 | 31, 32 | Android 12-13, Samsung flagship |
| galaxys23 | 33, 34 | Android 13-14, latest Samsung |

### Additional Parameters

```bash
# Set test timeout
--timeout=30m

# Add environment variables
--environment-variables="API_URL=https://api.example.com,DEBUG_MODE=true"

# Set network profile (for network testing)
--network-profile=4g-advanced

# Add test tags for organization
--test-labels="team=mobile,version=1.0.0,feature=login"

# Specify number of shards (for parallel execution)
--num-shards=3

# Set retry attempts for failed tests (0-5)
--test-num-flaky-test-attempts=2

# Enable video recording
--record-video

# Enable performance monitoring
--performance-metrics
```

## Retry Configuration

### Understanding Retry Attempts

The `--test-num-flaky-test-attempts` flag controls how many times Firebase Test Lab will retry failed tests:

- **Value Range**: 0-5 (default is 0, meaning no retries)
- **Behavior**: Only failed tests are retried, not the entire test suite
- **Counting**: A value of 2 means the test will be attempted up to 3 times total (1 initial + 2 retries)

### Retry Examples

```bash
# No retries (default behavior)
--test-num-flaky-test-attempts=0

# Retry failed tests once (2 total attempts)
--test-num-flaky-test-attempts=1

# Retry failed tests twice (3 total attempts) - recommended for flaky tests
--test-num-flaky-test-attempts=2

# Maximum retries (6 total attempts) - use cautiously
--test-num-flaky-test-attempts=5
```

### Best Practices for Retry Configuration

```bash
# For stable tests - no retries needed
gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --test-num-flaky-test-attempts=0

# For potentially flaky tests - 1 retry recommended
gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --test-num-flaky-test-attempts=1

# For known flaky tests - 2 retries maximum
gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --test-num-flaky-test-attempts=2
```

### Retry Cost Considerations

- **Higher retry values** increase test costs and duration
- **Recommended**: Start with 1 retry, increase to 2 only if necessary
- **CI/CD Impact**: Consider pipeline timeout when setting retry values
- **Flaky Test Strategy**: Use retries to identify flaky tests, then fix the underlying issues

## Monitoring Test Results

### Real-time Monitoring

```bash
# Watch test progress
gcloud firebase test ios list \
  --project=YOUR_GCP_PROJECT_ID \
  --format='table(name,state,deviceMatrixId,createTime)'
```

### Download Results

```bash
# Download test results
gcloud firebase test ios results download \
  --test=TEST_ID \
  --output-dir=test_results

# Download specific artifacts
gsutil cp -r gs://YOUR_TEST_RESULTS_BUCKET/TEST_RUN_ID/* ./results/
```

### Results Analysis

After completion, results include:
- **Test Logs**: Detailed execution logs
- **Screenshots**: Screenshots at key points
- **Videos**: Video recording of test execution
- **Performance Metrics**: CPU, memory, network usage
- **Coverage Data**: Code coverage reports (if enabled)

## Best Practices

### 1. Test Strategy
```bash
# Test on multiple iOS versions
--device model=iphone14,version=16.5
--device model=iphone15,version=17.0

# Test different screen orientations
--device model=iphone14,version=16.5,orientation=portrait
--device model=iphone14,version=16.5,orientation=landscape

# Test on both iPhone and iPad
--device model=iphone14,version=16.5
--device model=ipad9,version=16.5
```

### 2. Performance Optimization
```bash
# Use sharding for faster test execution
--num-shards=4

# Set reasonable timeout
--timeout=20m

# Use network profiles for realistic conditions
--network-profile=4g-basic
```

### 3. Results Management
```bash
# Use descriptive result directories
--results-dir="ios_tests_$(date +%Y%m%d_%H%M%S)"

# Add labels for better organization
--test-labels="build=${BUILD_NUMBER},branch=${BRANCH_NAME}"
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   ```bash
   # Re-authenticate
   gcloud auth login
   firebase login
   ```

2. **API Not Enabled**
   ```bash
   # Enable Firebase Test Lab API
   gcloud services enable testing.googleapis.com
   ```

3. **Permission Denied**
   ```bash
   # Check project permissions
   gcloud projects describe YOUR_GCP_PROJECT_ID
   ```

4. **Test Bundle Not Found**
   ```bash
   # Verify build artifacts exist
   ls -la build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun
   ```

### Debug Commands

```bash
# Check test status
gcloud firebase test ios describe TEST_ID

# List recent tests
gcloud firebase test ios list --limit=10

# Check available devices
gcloud firebase test ios models list

# Check available OS versions
gcloud firebase test ios versions list
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: iOS Tests on Firebase Test Lab

on:
  push:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.16.0'
        
    - name: Install dependencies
      run: flutter pub get
      
    - name: Build iOS test bundle
      run: patrol build ios --release --target integration_test/app_test.dart
      
    - name: Setup Google Cloud
      uses: google-github-actions/setup-gcloud@v0
      with:
        project_id: ${{ secrets.GCP_PROJECT_ID }}
        service_account_key: ${{ secrets.GCP_SA_KEY }}
        
    - name: Run tests on Firebase Test Lab
      run: |
        gcloud firebase test ios run \
          --type xctest \
          --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
          --device model=iphone14,version=16.5 \
          --results-bucket=gs://your-test-results \
          --results-dir=${{ github.run_number }}
```

### CircleCI Example

```yaml
version: 2.1

jobs:
  test:
    docker:
      - image: cimg/android:2023.10-node
    steps:
      - checkout
      - run:
          name: Install Flutter
          command: |
            wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.16.0-stable.tar.xz
            tar xf flutter.tar.xz
            export PATH="$PATH:`pwd`/flutter/bin"
            
      - run:
          name: Build and Test
          command: |
            export PATH="$PATH:`pwd`/flutter/bin"
            flutter pub get
            patrol build ios --release --target integration_test/app_test.dart
            
            gcloud firebase test ios run \
              --type xctest \
              --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
              --device model=iphone14,version=16.5
```

## Cost Optimization

1. **Use Smart Testing**: Test only changed components
2. **Parallel Execution**: Use sharding to reduce overall time
3. **Device Selection**: Test on representative devices, not all possible combinations
4. **Scheduled Testing**: Run comprehensive tests overnight or on weekends
5. **Result Caching**: Avoid redundant tests for unchanged code

## Advanced Features

### A/B Testing
```bash
# Test two different app versions
gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --app app_version_a.ipa \
  --results-bucket=gs://test_results \
  --results-dir="version_a"

gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --app app_version_b.ipa \
  --results-bucket=gs://test_results \
  --results-dir="version_b"
```

### Performance Testing
```bash
# Run performance-focused tests
gcloud firebase test ios run \
  --test build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun \
  --device model=iphone14,version=16.5 \
  --performance-metrics \
  --timeout=30m
```

---

**Related Documents:**
- [FTL Build Configuration Guide](./FTL_BUILD_README.md)
- [Firebase Test Lab Documentation](https://firebase.google.com/docs/test-lab)
- [Google Cloud SDK Documentation](https://cloud.google.com/sdk/docs)

**Last Updated:** October 28, 2025
**Compatible With:** Firebase Test Lab API, gcloud CLI, Firebase CLI
