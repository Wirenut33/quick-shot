#!/bin/bash
# Local-only, signed integration test. Does not touch /Applications or publish.
set -euo pipefail
cd "$(dirname "$0")/.."
test_root="$PWD/.build/UpdaterIntegration"
tools="$PWD/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
framework="$PWD/.build/Release/Build/Products/Release/QuickShot.app/Contents/Frameworks/Sparkle.framework"
[[ -d "$framework" ]] || { echo 'Run a signed scripts/release.sh build first.' >&2; exit 1; }
[[ ! -e "$test_root" ]] || { echo 'Use a fresh .build/UpdaterIntegration directory for this test.' >&2; exit 1; }
# Fixed loopback port and test-only paths must not be in use by another run.
mkdir -p "$test_root/QuickShotUpdateTest.app/Contents/MacOS" "$test_root/QuickShotUpdateTest.app/Contents/Frameworks" "$test_root/feed"
app="$test_root/QuickShotUpdateTest.app"
identity='Apple Development: MICHAEL ANTHONY MORALE (5K58FPSA8S)'
package_framework=$(find .build/SourcePackages/artifacts/sparkle -name Sparkle.framework -type d -print -quit)
xcrun swiftc -module-cache-path .build/SwiftModuleCache -F "$(dirname "$package_framework")" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks QuickShot/AppUpdater.swift Tests/UpdaterHost.swift \
  -o "$app/Contents/MacOS/QuickShotUpdateTest"
python3 - "$app" <<'PY'
import plistlib, sys
from pathlib import Path
info = plistlib.load(open('QuickShot/Info.plist','rb'))
info.update(CFBundleIdentifier='com.quickshot.QuickShot.UpdateTest', CFBundleName='QuickShotUpdateTest',
    CFBundleExecutable='QuickShotUpdateTest', CFBundleVersion='2', CFBundleShortVersionString='2.0',
    LSMinimumSystemVersion='15.0', SUFeedURL='http://127.0.0.1:18765/appcast.xml',
    NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
plistlib.dump(info, open(Path(sys.argv[1])/'Contents/Info.plist','wb'))
PY
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$identity" "$app"
ditto -c -k --keepParent "$app" "$test_root/feed/QuickShotUpdateTest-2.zip"
"$tools/generate_appcast" --account quickshot-updates --download-url-prefix http://127.0.0.1:18765/ --maximum-deltas 0 "$test_root/feed"
/usr/libexec/PlistBuddy -c 'Set CFBundleVersion 1' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleShortVersionString 1.0' "$app/Contents/Info.plist"
codesign --force --sign "$identity" "$app"
rm -f /tmp/quickshot-updater-host-version.txt
touch /tmp/quickshot-updater-busy
python3 -m http.server 18765 --bind 127.0.0.1 --directory "$test_root/feed" > "$test_root/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; pkill -x QuickShotUpdateTest || true; rm -f /tmp/quickshot-updater-busy' EXIT
for ((i=0;i<20;i++)); do
  if curl -fsS http://127.0.0.1:18765/appcast.xml >/dev/null; then break; fi
  sleep 1
done
kill -0 "$server_pid"
open -n "$app"
for ((i=0;i<60;i++)); do
  if grep -q 'GET /QuickShotUpdateTest-2.zip.*200' "$test_root/server.log"; then break; fi
  sleep 1
done
grep -q 'GET /QuickShotUpdateTest-2.zip.*200' "$test_root/server.log"
sleep 20
[[ "$(cat /tmp/quickshot-updater-host-version.txt)" == 1 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")" == 1 ]]
echo 'PASS: downloaded update held while busy'
rm /tmp/quickshot-updater-busy
for ((i=0;i<60;i++)); do
  if [[ "$(cat /tmp/quickshot-updater-host-version.txt)" == 2 ]]; then
    echo 'PASS: signed update installed and version 2 relaunched when idle'
    exit 0
  fi
  sleep 1
done
echo 'FAIL: timed out waiting for automatic installation' >&2
exit 1
