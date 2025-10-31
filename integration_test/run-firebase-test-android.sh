#!/bin/bash

chmod +x ./run-firebase-test.sh
# Firebase Test Lab command for Android
gcloud firebase test android run \
  --type=instrumentation \
  --app=/Users/lucian.cernauteanuthinslices.com/Documents/Repos/patrol-workshop/build/app/outputs/flutter-apk/app-debug.apk \
  --test=/Users/lucian.cernauteanuthinslices.com/Documents/Repos/patrol-workshop/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
  --device model=Pixel2.arm,version=33,locale=en,orientation=portrait \
  --timeout=10m \
  --num-flaky-test-attempts=0
