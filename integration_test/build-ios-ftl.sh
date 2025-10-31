#!/bin/bash
chmod +x ./build-ios-ftl.sh
# Build iOS for Firebase Test Lab
set -e

rm -rf build/ios_integ
rm -rf ios/build

patrol build ios \
  --target integration_test/quiz_test.dart \
  --release \
  --flavor prod