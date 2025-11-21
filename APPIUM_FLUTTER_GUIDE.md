# Fixing Appium Flutter Driver Issue

## Problem
The app is stuck at splash screen because Appium Flutter driver cannot connect to the Flutter app. The logs show:
```
Error accessing UiAutomation accessibility node for window, skipping.
```

## Why This Happens
Appium Flutter Driver requires the app to be built with special integration. Without it:
- The app launches normally
- But waits indefinitely for the Flutter driver to connect
- Appium cannot find Flutter widgets
- App appears "stuck" at splash screen

## Solutions

### ✅ Solution 1: Use UiAutomator2 (APPLIED)
**Best for most cases** - Allows the app to run normally.

Changed in script:
```bash
"automationName":"UiAutomator2"  # Was: "Flutter"
```

**Pros:**
- ✅ App runs normally without waiting for driver
- ✅ Works with any Flutter app
- ✅ Uses native Android accessibility
- ✅ No special build configuration needed

**Cons:**
- ❌ Cannot directly interact with Flutter widgets
- ❌ Must use native Android selectors (resource-id, content-desc, etc.)

### Solution 2: Build App with Flutter Driver Integration
**Only if you need Flutter-specific widget testing**

#### Requirements:
1. Add `appium_flutter_driver` dependency
2. Build with Flutter driver extension enabled
3. Use Patrol's native automation instead

#### Steps:

**1. Add to `pubspec.yaml`:**
```yaml
dev_dependencies:
  appium_flutter_driver: ^1.0.1
```

**2. Build command:**
```bash
# Enable Flutter driver extension during build
flutter build apk --dart-define=FLUTTER_DRIVER=true
```

**3. Update app entrypoint** (if using custom integration):
```dart
import 'package:flutter_driver/driver_extension.dart';

void main() {
  // Enable Flutter driver only in integration test builds
  if (const bool.fromEnvironment('FLUTTER_DRIVER')) {
    enableFlutterDriverExtension();
  }
  runApp(MyApp());
}
```

### ⚠️ Important Note on Patrol + Kobiton
**Patrol's architecture** uses native automation (UiAutomator2/XCUITest) under the hood, NOT Flutter driver. Therefore:

- **Recommended**: Use `automationName: "UiAutomator2"`
- Patrol tests will execute properly via native automation
- Flutter driver is only needed for direct widget inspection in Appium

## Current Status
✅ Script updated to use `UiAutomator2`
✅ App should now run normally
✅ Patrol tests can execute via native automation

## Next Steps
1. End any existing Kobiton sessions
2. Run the updated script:
   ```bash
   bash integration_test/run-kobiton-android-v2.sh
   ```
3. App should now launch and run past the splash screen
