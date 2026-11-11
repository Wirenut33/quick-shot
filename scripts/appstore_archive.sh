#!/bin/bash
# Archives the sandboxed App Store build and exports a signed installer package for
# App Store Connect. Run on a Mac signed in to Xcode with a paid Apple Developer
# Program team. Nothing is uploaded; see docs/APP_STORE.md for the remaining steps.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
# App Store Connect needs a build number higher than any already uploaded for this version.
build=${APPSTORE_BUILD:-$(git rev-list --count HEAD)}
out=".build/appstore/build-$build"
if [[ -e "$out" ]]; then echo "Output already exists: $out" >&2; exit 1; fi
mkdir -p "$out"
settings=(DEVELOPMENT_TEAM="$TEAM_ID" CURRENT_PROJECT_VERSION="$build" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO)
if [[ -n "${APPSTORE_VERSION:-}" ]]; then settings+=(MARKETING_VERSION="$APPSTORE_VERSION"); fi
if [[ -n "${APPSTORE_BUNDLE_ID:-}" ]]; then settings+=(PRODUCT_BUNDLE_IDENTIFIER="$APPSTORE_BUNDLE_ID"); fi
xcodebuild -project QuickShot.xcodeproj -scheme QuickShot-AppStore -configuration Release \
  -derivedDataPath .build/AppStoreArchive -archivePath "$out/QuickShot.xcarchive" \
  -allowProvisioningUpdates "${settings[@]}" archive
python3 scripts/verify_appstore.py "$out/QuickShot.xcarchive/Products/Applications/QuickShot.app"
sed "s/__TEAM_ID__/$TEAM_ID/" AppStore/ExportOptions.plist > "$out/ExportOptions.plist"
xcodebuild -exportArchive -archivePath "$out/QuickShot.xcarchive" -exportPath "$out/export" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates
echo "Exported $(ls "$out"/export/*.pkg). Upload it with the Transporter app, then finish in App Store Connect."
