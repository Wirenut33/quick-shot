# QuickShot

A lightweight macOS menu bar app for capturing, marking up and sharing screenshots.

## Features

- **Capture from anywhere.** Global keyboard shortcuts for full screen, selection, window and text capture. You choose them; nothing is registered until you accept the suggestions in the welcome guide.
- **Frozen-screen selection.** The screen freezes the moment you start, so open menus and hover states stay put. A crosshair and a live pixel readout help you select exactly. Press **Space** to pick a window instead, **Esc** to cancel.
- **Capture Text.** Drag over any area to copy its text, or the contents of a QR code, to the clipboard. Recognition runs on your Mac.
- **Markup editor.** Rectangle, arrow, line, polyline, highlight, text and redact tools, each with a one-key shortcut. Type labels directly on the image. Every tool remembers its own colour and style.
- **Redact.** Cover secrets with an opaque fill, or pixelate them when the shape should stay recognisable.
- **Zoom.** Fit to window, true size, or step in and out.
- **Save in one step.** Choose a folder once and **⌘S** saves there without asking. Files never overwrite each other.
- **Snapshot Collection.** Gather several captures, then copy them together as separate attachments or as one image.
- **Private by design.** No account, no analytics, no uploads. See [PRIVACY.md](PRIVACY.md).

## Requirements

- macOS 15.0 or later
- Xcode 26 or later to build

## Two builds from one codebase

| | Direct build | App Store build |
|---|---|---|
| Scheme | `QuickShot` | `QuickShot-AppStore` |
| App Sandbox | Off | On |
| Updates | Sparkle, automatic | Through the App Store |
| Bundle ID | `com.quickshot.QuickShot` | `com.michaelmorale.QuickShot` |

Both use the same capture engine (ScreenCaptureKit) and the same features. Code that only one build needs is wrapped in `#if !APPSTORE`. The App Store build's `Info.plist`, entitlements and export options live in `AppStore/`. See [docs/APP_STORE.md](docs/APP_STORE.md) for how to submit.

## Setup

```bash
git clone https://github.com/Wirenut33/quick-shot.git
cd quick-shot
open QuickShot.xcodeproj
```

Pick the `QuickShot` scheme and run (⌘R). The welcome guide opens on first launch and walks through Screen Recording permission and shortcuts.

## Usage

QuickShot appears as a camera icon in the menu bar.

- **Capture Full Screen** captures the display under the pointer.
- **Capture Selection** lets you drag an area. Press **Space** to switch to picking a window.
- **Capture Window** starts in window-picking mode.
- **Capture Text** copies the text in the area you drag over.
- **Collect Snapshots** keeps captures in the Snapshot Collection instead of the clipboard.
- **Annotate Before Copying** opens the editor after each capture. Turn it off to copy captures straight to the clipboard.
- **Settings…** holds the save folder, shortcuts, launch at login and the welcome guide.

A short on-screen confirmation follows every copy, save and text capture.

### Shortcuts

Global shortcuts are set in the welcome guide or in **Settings › Shortcuts**. The suggestions are **⇧⌘1** for full screen and **⇧⌘2** for selection. QuickShot refuses shortcuts that macOS itself has reserved, and tells you when a shortcut could not be registered.

### Editor

| Key | Action |
|---|---|
| V R A L P H T B | Select, Rectangle, Arrow, Line, Polyline, Highlight, Text, Redact |
| ⌘↩ | Copy and close |
| ⌘C | Copy (while the canvas has focus) |
| ⌘S / ⇧⌘S | Save to the chosen folder / choose where to save |
| ⌘+ ⌘− ⌘0 ⌘1 | Zoom in, zoom out, true size, fit to window |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌫ | Delete the selected mark |
| Esc | Cancel the current step, then deselect, then close |

Tool keys work while the canvas has focus; while you type in a label or the description they type text.

- Draw a mark and it becomes selected. Drag it to move it; drag corner handles to resize. Text corner handles resize the font.
- **Text:** click where the label belongs and type. Return finishes, Esc cancels. Double-click a label to edit it.
- **Arrow and line:** drag either end to reposition it. Drag an arrow's middle handle to bend it. Slide a line's middle dot along the line, or pull it away to curve the line.
- **Polyline:** click to add points, or drag to lay down a segment. Double-click or press Return to finish; Delete removes the last point. Switching tools keeps a polyline that has two or more points.
- **Highlight** draws a translucent area that keeps the content beneath it.
- **Redact** defaults to an opaque fill, the only style that cannot be read back. Pixelate uses coarse blocks and is meant for faces and shapes, not for secrets.
- **Esc never discards work by surprise.** If there is unsaved markup, the first Esc says so and a second one closes the window.
- **Copy Text** reads the image as it will be exported, so redacted text stays out.

### Snapshot Collection

1. Turn on **Collect Snapshots**. The count appears beside the camera.
2. Capture as often as you like. With **Annotate Before Copying** off, each capture is stored at once. With it on, mark up the capture and choose **Add to Collection**.
3. Open **Snapshot Collection**, select what you want (⌘-click, Shift-click or Select All) and choose **Copy Selected**.
4. Paste into another app. QuickShot supplies separate PNG attachments. Apps decide how many they accept; use **Copy as One Image** when an app takes only one.

Snapshots stay on disk across restarts until you remove them (they go to the Trash). **Show Folder** opens them in Finder.

## Permissions

QuickShot needs **Screen & System Audio Recording** permission. The welcome guide asks for it; you can also enable it in **System Settings › Privacy & Security › Screen & System Audio Recording**. If macOS offers **Quit & Reopen**, accept it; the welcome guide returns afterwards. On macOS 15 and later the system periodically asks you to confirm that QuickShot may keep capturing the screen. That reminder comes from macOS and applies to every screenshot app.

Launch at login is off until you turn it on.

To keep the permission across rebuilds of the direct build, sign each release with the same identity; macOS treats ad-hoc signed rebuilds as different apps.

## Testing

```bash
bash scripts/validate.sh
```

This runs the release-contract tests, the collection, annotation and capture tests, builds the direct app for both architectures, and builds the App Store app ad-hoc signed so the sandbox entitlements that are really in the binary can be checked.

```bash
bash scripts/live_capture_check.sh
```

This exercises the real capture path (ScreenCaptureKit, the selection overlay, window picking and text capture) with synthesized input. The terminal running it needs Screen Recording permission, and the overlay flashes on screen while it runs. It is not part of CI.

Debug builds accept `--capture-self-test`, which captures every display and writes `QuickShot-capture-self-test.txt` to the temporary directory. The direct build also accepts `--collection-capture-test`, `--editor-smoke-test` and `--capture-full`. None of these exist in the App Store build.

`xcrun swift scripts/generate_icon.swift QuickShot/Assets.xcassets/AppIcon.appiconset` redraws the app icon at every size.

## Automatic updates (direct build)

The direct build checks for signed updates hourly, downloads them, and installs when no capture or editor is open. **A merge to `main` publishes an update to every installed copy.** See [docs/AUTOMATIC_UPDATES.md](docs/AUTOMATIC_UPDATES.md).

## Author

Michael Morale

## License

MIT License
