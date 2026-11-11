#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s Tests -p 'test_*.py' -v
mkdir -p .build
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/SnapshotCollection.swift Tests/CollectionTests.swift -o .build/collection-tests
.build/collection-tests
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/AnnotationDocument.swift QuickShot/AnnotationCanvasView.swift Tests/AnnotationTests.swift -o .build/annotation-tests
.build/annotation-tests
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/CaptureGeometry.swift QuickShot/Shortcut.swift QuickShot/HotKeyCenter.swift QuickShot/AppSettings.swift QuickShot/AnnotationDocument.swift QuickShot/TextRecognizer.swift Tests/CaptureTests.swift -o .build/capture-tests
.build/capture-tests
xcodebuild -project QuickShot.xcodeproj -scheme QuickShot -configuration Release \
  -derivedDataPath .build/CI -clonedSourcePackagesDirPath .build/SourcePackages \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
# One architecture per call: newer lipo releases reject several after -verify_arch.
for arch in arm64 x86_64; do
  lipo .build/CI/Build/Products/Release/QuickShot.app/Contents/MacOS/QuickShot -verify_arch "$arch"
done
# The App Store build is a second target with its own output folder, so a stale
# Sparkle.framework from the direct build can never be mistaken for part of it.
# Ad-hoc signing lets the check read the entitlements that are really in the app.
xcodebuild -project QuickShot.xcodeproj -scheme QuickShot-AppStore -configuration Release \
  -derivedDataPath .build/CI-AppStore -clonedSourcePackagesDirPath .build/SourcePackages \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
python3 scripts/verify_appstore.py .build/CI-AppStore/Build/Products/Release-AppStore/QuickShot.app
# The direct build keeps its updater.
test -d .build/CI/Build/Products/Release/QuickShot.app/Contents/Frameworks/Sparkle.framework
