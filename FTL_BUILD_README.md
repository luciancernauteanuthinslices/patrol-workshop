# Firebase Test Lab Build Configuration Guide

This guide documents the solution for building iOS and Android bundles for Firebase Test Lab (FTL) with Patrol in Flutter projects that use Firebase and Google Sign-In dependencies.

## Problem Overview

When building bundles for Firebase Test Lab, several platform-specific issues can occur:

### iOS Issues
When building iOS bundles with `patrol build ios --release --target integration_test/your_test.dart`:

1. **CocoaPods Dependency Conflicts** - Version mismatches between Firebase and Google Sign-In dependencies
2. **Code Signing Issues** - FTL builds fail due to provisioning profile requirements
3. **Firebase SDK Compatibility** - Header inclusion issues with newer Firebase versions
4. **iOS Deployment Target** - Minimum iOS version constraints

### Android Issues
When building Android bundles with `patrol build android --release --target integration_test/your_test.dart`:

1. **ProGuard/R8 Configuration** - Code obfuscation breaking test instrumentation
2. **SDK Version Conflicts** - Incompatible Android SDK/compile versions
3. **Manifest Configuration** - Missing permissions or test configuration
4. **Debug vs Release Configuration** - Test runner not properly configured for release builds

## Solution Overview

The solution involves updating platform-specific configuration files to ensure compatibility and proper FTL build setup for both iOS and Android.

## Configuration Changes

## iOS Configuration

### 1. iOS/Podfile

Add the following configurations to your `ios/Podfile`:

```ruby
platform :ios, '14.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

# Override Firebase SDK version to be compatible with GoogleSignIn 8.0
$FirebaseSDKVersion = '11.0.0'

# ... (rest of Podfile)

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    target.build_configurations.each do |config|
      # Set minimum deployment target for all pods
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
      
      # Disable code signing for FTL builds
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      
      # Fix for Firebase 11.x modular header issue
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_NOTIFICATIONS=1',
      ]
    end
  end
end
```

### 2. iOS/Runner.xcodeproj/project.pbxproj

Update the Release-dev configuration for both `Runner` and `RunnerUITests` targets:

**For Runner Target (Release-dev configuration):**
```xml
CODE_SIGNING_ALLOWED = NO;
CODE_SIGNING_REQUIRED = NO;
CODE_SIGN_IDENTITY = "";
CODE_SIGN_STYLE = Manual;
DEVELOPMENT_TEAM = "";
CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES;
```

**For RunnerUITests Target (Release-dev configuration):**
```xml
CODE_SIGNING_ALLOWED = NO;
CODE_SIGNING_REQUIRED = NO;
CODE_SIGN_IDENTITY = "";
CODE_SIGN_STYLE = Manual;
DEVELOPMENT_TEAM = "";
```

### 3. pubspec.yaml (Optional Updates)

Ensure compatible Firebase package versions:

```yaml
dependencies:
  firebase_auth: ^4.16.0
  firebase_core: ^2.24.0
  google_sign_in: ^6.1.5
```

## Android Configuration

### 1. android/build.gradle

Update your `android/build.gradle` for proper FTL compatibility:

```gradle
buildscript {
    ext.kotlin_version = '1.9.10'
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
        classpath 'com.google.gms:google-services:4.4.0'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
```

### 2. android/app/build.gradle

Update your `android/app/build.gradle`:

```gradle
android {
    namespace 'pl.leancode.patrol.challenge'
    compileSdkVersion 34
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
    }

    defaultConfig {
        applicationId "pl.leancode.patrol.challenge"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
        
        // FTL Configuration
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
        testInstrumentationRunnerArguments clearPackageData: 'true'
    }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            
            // FTL: Disable obfuscation for test builds
            proguardFiles file('proguard-test-rules.pro')
        }
        debug {
            signingConfig signingConfigs.debug
        }
        profile {
            initWith debug
            signingConfig signingConfigs.debug
        }
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    
    // Firebase dependencies
    implementation platform('com.google.firebase:firebase-bom:32.6.0')
    implementation 'com.google.firebase:firebase-auth'
    implementation 'com.google.firebase:firebase-core'
    
    // Google Sign-In
    implementation 'com.google.android.gms:play-services-auth:20.7.0'
    
    // Test dependencies for FTL
    androidTestImplementation 'androidx.test.ext:junit:1.1.5'
    androidTestImplementation 'androidx.test.espresso:espresso-core:3.5.1'
    androidTestImplementation 'androidx.test:runner:1.5.2'
    androidTestImplementation 'androidx.test:rules:1.5.0'
}
```

### 3. android/app/proguard-test-rules.pro

Create `android/app/proguard-test-rules.pro` for FTL builds:

```proguard
# Keep Patrol test classes
-keep class pl.leancode.patrol.** { *; }
-keep class integration_test.** { *; }

# Keep Firebase test classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep test instrumentation
-keep class androidx.test.** { *; }
-keep class junit.** { *; }

# Prevent obfuscation of test-related classes
-keepnames class * extends android.app.Activity
-keepnames class * extends android.app.Application
-keepnames class * extends android.app.Service
-keepnames class * extends android.content.BroadcastReceiver
-keepnames class * extends android.content.ContentProvider

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
```

### 4. android/app/src/main/AndroidManifest.xml

Ensure your `AndroidManifest.xml` has proper test configuration:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    
    <!-- Required permissions for FTL -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    
    <!-- Test permissions -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    
    <application
        android:label="Challenge"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        
        <!-- FTL Test configuration -->
        <uses-library android:name="android.test.runner" />
        
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
                
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
```

## Key Changes Explained

### iOS Changes Explained

### 1. Firebase SDK Version Override
```ruby
$FirebaseSDKVersion = '11.0.0'
```
- Forces Firebase iOS SDK to use version 11.0.0
- This version uses GoogleUtilities 8.0, which is compatible with GoogleSignIn 8.0
- Resolves the CocoaPods dependency conflict

### 2. iOS Deployment Target
```ruby
platform :ios, '14.0'
```
- Increases minimum iOS version from 13.0 to 14.0
- Required by GoogleSignIn 8.0 and Firebase 11.0.0

### 3. Code Signing Configuration
```ruby
config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
```
- Disables code signing for FTL builds
- FTL doesn't require signed binaries for testing
- Prevents provisioning profile errors

### 4. Firebase Header Compatibility
```ruby
config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
```
- Fixes modular header inclusion errors in Firebase 11.x
- Allows non-modular header includes in framework modules

### Android Changes Explained

### 5. Android SDK Configuration
```gradle
compileSdkVersion 34
minSdkVersion 21
targetSdkVersion 34
```
- Uses Android SDK 34 for latest API compatibility
- Minimum SDK 21 ensures broad device coverage
- Target SDK 34 for optimal performance and features

### 6. ProGuard/R8 Configuration
```gradle
minifyEnabled false
proguardFiles file('proguard-test-rules.pro')
```
- Disables code obfuscation for FTL builds
- Custom ProGuard rules preserve test classes
- Prevents test instrumentation failures

### 7. Test Instrumentation Configuration
```gradle
testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
testInstrumentationRunnerArguments clearPackageData: 'true'
```
- Configures proper test runner for Patrol
- Clears app data between tests for consistency

## Build Commands

### Clean Build (iOS)
```bash
# Clean everything
flutter clean
rm -rf ios/Pods ios/Podfile.lock build
flutter pub get

# Build iOS for FTL
patrol build ios --release --target integration_test/your_test.dart
```

### Clean Build (Android)
```bash
# Clean everything
flutter clean
rm -rf build
flutter pub get

# Build Android for FTL
patrol build android --release --target integration_test/your_test.dart
```

### Standard iOS Build
```bash
patrol build ios --release --target integration_test/your_test.dart
```

### Standard Android Build
```bash
patrol build android --release --target integration_test/your_test.dart
```

### Cross-Platform Build
```bash
# Build both platforms for comprehensive FTL testing
patrol build ios --release --target integration_test/your_test.dart
patrol build android --release --target integration_test/your_test.dart
```

## Expected Build Output

### iOS Build Output
```
build/ios_integ/Build/Products/Release-iphoneos/Runner.app                    # App under test
build/ios_integ/Build/Products/Release-iphoneos/RunnerUITests-Runner.app      # Test instrumentation app  
build/ios_integ/Build/Products/dev_dev_iphoneos26.0-arm64.xctestrun          # XCTest run file
```

### Android Build Output
```
build/app/outputs/apk/release/app-release.apk                                # App under test
build/app/outputs/apk/androidTest/release/app-release-androidTest.apk        # Test instrumentation app
```

Both platforms are ready for Firebase Test Lab upload and cross-platform testing.

## Common Issues & Solutions

### iOS Issues

### 1. "No profiles found" Error
**Problem:** Xcode looking for provisioning profiles
**Solution:** Ensure `CODE_SIGNING_REQUIRED` and `CODE_SIGNING_ALLOWED` are set to 'NO' for both targets

### 2. "GoogleUtilities/Logger version conflict"  
**Problem:** Firebase and GoogleSignIn requiring different GoogleUtilities versions
**Solution:** Set `$FirebaseSDKVersion = '11.0.0'` in Podfile

### 3. "Non-modular header include" errors
**Problem:** Firebase 11.x stricter header requirements
**Solution:** Add `CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = 'YES'`

### 4. "Higher minimum iOS deployment version" errors
**Problem:** GoogleSignIn 8.0 requiring iOS 14.0+
**Solution:** Update platform to iOS 14.0 in both Podfile and Xcode project

### Android Issues

### 5. "Test runner not found" Error
**Problem:** Android test instrumentation not properly configured
**Solution:** Add `testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"` to build.gradle

### 6. "Obfuscation breaking tests" Error
**Problem:** ProGuard/R8 obfuscating test classes and breaking instrumentation
**Solution:** Set `minifyEnabled false` for release builds and add custom ProGuard rules

### 7. "Permission denied" Error in FTL
**Problem:** Missing permissions in AndroidManifest.xml
**Solution:** Add required permissions: INTERNET, ACCESS_NETWORK_STATE, storage permissions

### 8. "SDK version not found" Error
**Problem:** Android SDK 34 not installed or configured
**Solution:** Update Android SDK and set `compileSdkVersion 34` in build.gradle

## Firebase Test Lab Upload

After successful build, upload the following to Firebase Test Lab:

### iOS Upload
1. `Runner.app` (main application)
2. `RunnerUITests-Runner.app` (test bundle)
3. `.xctestrun` file (test configuration)

### Android Upload  
1. `app-release.apk` (main application)
2. `app-release-androidTest.apk` (test instrumentation app)

### Cross-Platform Testing
Upload both iOS and Android artifacts to test on:
- Multiple iOS devices (iPhone 14/15, iPad)
- Multiple Android devices (various OEMs and screen sizes)
- Different OS versions (iOS 16.x/17.x, Android 8.x/9.x/10.x/11.x/12.x/13.x/14.x)

## Compatibility

This solution has been tested with:

### iOS Compatibility
- Flutter: ^3.16.0
- Patrol: ^3.19.0  
- Firebase SDK: 11.0.0
- GoogleSignIn: ^6.1.5
- iOS Deployment Target: 14.0
- Xcode: 14.3+

### Android Compatibility
- Flutter: ^3.16.0
- Patrol: ^3.19.0
- Firebase BOM: 32.6.0
- Android SDK: 34
- Android Gradle Plugin: 8.1.0
- Kotlin: 1.9.10
- Min SDK: 21
- Target SDK: 34

## Notes

### Platform-Specific Considerations
- **iOS**: Code signing is disabled for FTL builds only
- **Android**: Minification is disabled for test builds to preserve class names
- Consider using separate build configurations for FTL vs production
- Always test on real devices after configuration changes
- Keep Firebase and Google Sign-In versions updated for security patches

## Troubleshooting

### iOS Troubleshooting
If iOS issues persist:
1. Verify all changes are applied to both Debug and Release configurations if needed
2. Clean and rebuild completely: `flutter clean && rm -rf ios/Pods ios/Podfile.lock`
3. Check that the Firebase SDK version override is properly set in Podfile
4. Verify iOS deployment target is consistent across all targets
5. Ensure Xcode project settings match Podfile configurations

### Android Troubleshooting
If Android issues persist:
1. Clean and rebuild: `flutter clean && rm -rf build`
2. Verify Android SDK 34 is installed: `sdkmanager "platforms;android-34"`
3. Check ProGuard rules file exists and is properly formatted
4. Verify test dependencies are included in build.gradle
5. Ensure AndroidManifest.xml has proper test library declarations

### Cross-Platform Troubleshooting
1. Verify pubspec.yaml has compatible dependency versions
2. Check that Patrol version supports both platforms
3. Ensure test files exist and are properly structured
4. Verify Firebase project configuration is correct

---

**Last Updated:** October 28, 2025
**Compatible With:** Flutter 3.16+, Patrol 3.19+, Firebase iOS SDK 11.0.0, Android SDK 34
