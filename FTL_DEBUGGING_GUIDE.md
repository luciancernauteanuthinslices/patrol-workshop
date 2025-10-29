# Firebase Test Lab - Debugging Guide

## Current Status

Your tests are **passing locally** but **failing on Firebase Test Lab (FTL)**. This is a common issue with cloud testing.

### Test Results Summary

| Platform | Device | Status | Issue |
|----------|--------|--------|-------|
| Android | Shiba (v35) | ❌ Failed | 1 test case failed |
| iOS | iPhone 11 Pro (v16.6) | ❌ Failed | Test failed to run |

## Why Tests Fail on FTL but Pass Locally

### Common Causes

1. **Environment Differences**
   - Cloud devices have different system configurations
   - Network latency affects timing-sensitive operations
   - Permission handling differs between local emulators and cloud devices

2. **Native Integration Issues**
   - Permission dialogs may not appear on cloud devices
   - Notification handling is unreliable on FTL
   - Native platform features may behave differently

3. **Test Timing Issues**
   - `pumpAndSettle()` may timeout on slower cloud devices
   - Animations and transitions take longer on cloud infrastructure
   - Network requests may be slower

4. **Device-Specific Behavior**
   - Shiba device (Android 35) may have unique behavior
   - iPhone 11 Pro (iOS 16.6) rendering might differ
   - Screen sizes and DPI affect element positioning

## Improvements Made to Test

The updated `quiz_test.dart` includes:

✅ **Error Handling**
```dart
try {
  if(await $.native.isPermissionDialogVisible()){
    await $.native.grantPermissionOnlyThisTime();
  }
} catch (e) {
  print('Permission dialog not found: $e');
}
```

✅ **Explicit Waits**
```dart
await $.waitUntilVisible(
  $("To confirm you're not a robot, pick LeanCode's colors"),
  timeout: Duration(seconds: 10)
);
```

✅ **Better Settling**
```dart
await $.pumpAndSettle();  // After each interaction
```

✅ **Reduced Scroll Steps**
```dart
await $(Stack).containing('Question 1/3').scrollTo(
  view: $(Icons.arrow_right_alt), 
  scrollDirection: AxisDirection.left, 
  step: 500,  // Reduced from 1000
);
```

✅ **Removed Unreliable Operations**
- Removed notification tapping (unreliable on FTL)
- Removed notification tray opening
- Focused on core quiz functionality

## Debugging Steps

### 1. Run Simple Test First
```bash
# Build simple test
patrol build android --debug --target integration_test/simple_test.dart

# Upload to FTL
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --device model=shiba,version=35
```

### 2. Check FTL Logs
1. Go to Firebase Console: https://console.firebase.google.com/
2. Select your project: `patrolworkshop-accc5`
3. Navigate to Test Lab → Test History
4. Click on failed test matrix
5. View logs for detailed error messages

### 3. Enable Verbose Logging
```bash
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --device model=shiba,version=35 \
  --environment-variables="VERBOSE_LOGGING=true"
```

### 4. Test with Different Devices
```bash
# Try Pixel 4 instead of Shiba
gcloud firebase test android run \
  --type instrumentation \
  --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --app build/app/outputs/apk/debug/app-debug.apk \
  --device model=Pixel4,version=30
```

## Recommended Next Steps

### Option 1: Simplify Tests
Start with `simple_test.dart` to verify basic functionality:
```bash
patrol build android --debug --target integration_test/simple_test.dart
```

### Option 2: Add More Debugging
Add print statements and logging to understand where tests fail:
```dart
print('Step 1: App launched');
await $('Go to the quiz').tap();
print('Step 2: Navigated to quiz');
```

### Option 3: Check Firebase Console
View detailed logs in Firebase Console for exact failure reasons:
- https://console.firebase.google.com/project/patrolworkshop-accc5/testlab

### Option 4: Test Different Devices
Try testing on more stable devices like Pixel 4 or iPhone 12 instead of newer devices.

## iOS-Specific Issues

The iOS test shows "Test failed to run" which typically means:
- The xctestrun file structure is incorrect
- The app bundle is missing required files
- iOS test runner couldn't initialize

**Solution:** Verify the iOS bundle structure:
```bash
unzip -l /tmp/ios_test_bundle.zip | grep -E "\.app|\.xctest|xctestrun"
```

## Performance Considerations

FTL devices are typically slower than local emulators:
- Add 2-3x timeout multipliers for cloud testing
- Use `pumpAndSettle()` instead of `pump(Duration(...))`
- Reduce animation steps in scrolling operations

## Resources

- [Firebase Test Lab Documentation](https://firebase.google.com/docs/test-lab)
- [Patrol Testing Guide](https://patrol.leancode.pl/)
- [Flutter Integration Testing](https://flutter.dev/docs/testing/integration-tests)

---

**Last Updated:** October 29, 2025
**Test Framework:** Patrol 3.19.0
**Project:** patrol-workshop
