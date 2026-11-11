#!/bin/bash
# Local-only check of the real capture path. The terminal running it needs Screen
# Recording permission. The selection overlay flashes on screen a few times while
# synthesized events drive it. Nothing from the screen is written to disk.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/CaptureEngine.swift QuickShot/CaptureGeometry.swift \
  QuickShot/SelectionOverlay.swift QuickShot/ScreenshotManager.swift QuickShot/Shortcut.swift QuickShot/HotKeyCenter.swift \
  QuickShot/TextRecognizer.swift \
  Tests/LiveCaptureTests.swift -o .build/live-capture-tests
.build/live-capture-tests
