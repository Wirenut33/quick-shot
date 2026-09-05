#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s Tests -p 'test_*.py' -v
mkdir -p .build
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/SnapshotCollection.swift Tests/CollectionTests.swift -o .build/collection-tests
.build/collection-tests
xcodebuild -project QuickShot.xcodeproj -scheme QuickShot -configuration Release \
  -derivedDataPath .build/CI -clonedSourcePackagesDirPath .build/SourcePackages \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
lipo .build/CI/Build/Products/Release/QuickShot.app/Contents/MacOS/QuickShot -verify_arch arm64 x86_64
