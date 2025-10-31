#!/bin/bash

# Run iOS tests on Firebase Test Lab
cd build/ios_integ/Build/Products

# 1) sanity checks
test -f "Release-dev-iphoneos/Runner.app/Info.plist"
test -f "Release-dev-iphoneos/RunnerUITests-Runner.app/Info.plist"

# 2) rename the xctestrun to the device OS (e.g., 18.3)
XCT=$(ls -1 dev_dev_iphoneos*.xctestrun | head -n1)
cp -f "$XCT" "dev_dev_iphoneos18.3-arm64.xctestrun"

# 3) zip EXACTLY these at zip root
zip -r ios_tests.zip Release-dev-iphoneos dev_dev_iphoneos18.3-arm64.xctestrun

# 4) run on FTL
gcloud firebase test ios run \
  --test "$(pwd)/ios_tests.zip" \
  --device model=iphone16pro,version=18.3,locale=en_US,orientation=portrait
