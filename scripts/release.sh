#!/bin/bash
# Builds locally with Keychain keys, or in CI with its temporary signing keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_VERSION:?Set RELEASE_VERSION}"
: "${RELEASE_BUILD:?Set RELEASE_BUILD}"
: "${RELEASE_TAG:?Set RELEASE_TAG}"
identity='Apple Development: MICHAEL ANTHONY MORALE (5K58FPSA8S)'
out=".build/releases/$RELEASE_TAG"
# Never mutate or silently reuse a previously generated release directory.
if [[ -e "$out" ]]; then echo "Release output already exists: $out" >&2; exit 1; fi
mkdir -p "$out"
xcodebuild -project QuickShot.xcodeproj -scheme QuickShot -configuration Release \
  -derivedDataPath .build/Release -clonedSourcePackagesDirPath .build/SourcePackages \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual \
  MARKETING_VERSION="$RELEASE_VERSION" CURRENT_PROJECT_VERSION="$RELEASE_BUILD" build
app=.build/Release/Build/Products/Release/QuickShot.app
archive="$out/QuickShot-$RELEASE_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
tools=.build/SourcePackages/artifacts/sparkle/Sparkle/bin
args=(--maximum-deltas 0 --maximum-versions 1 --download-url-prefix "https://github.com/Wirenut33/quick-shot/releases/download/$RELEASE_TAG/")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - "${args[@]}" "$out"
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - --verify "$out/appcast.xml"
else
  "$tools/generate_appcast" --account quickshot-updates "${args[@]}" "$out"
  "$tools/sign_update" --account quickshot-updates --verify "$out/appcast.xml"
fi
signature=$(python3 - "$out/appcast.xml" <<'PYCODE'
import sys
from xml.etree import ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PYCODE
)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - --verify "$archive" "$signature"
else
  "$tools/sign_update" --account quickshot-updates --verify "$archive" "$signature"
fi
python3 scripts/verify_release.py "$app" "$out/appcast.xml" "$archive" "$RELEASE_VERSION" "$RELEASE_BUILD" "$RELEASE_TAG"
(cd "$out" && shasum -a 256 "QuickShot-$RELEASE_VERSION.zip" > SHA256SUMS.txt)
