# QuickShot

A lightweight macOS menu bar app for capturing and annotating screenshots.

## Features

- **Capture & Annotate** - Full-screen, selection, and window captures open directly in the editor
- **Annotation Toggle** - Turn annotation off to copy a capture directly to the clipboard
- **Minimal Red Markup** - Add rectangles, arrows, and text without a complicated drawing tool
- **Expandable Canvas** - Add working room around a screenshot and include a written description
- **Copy & Close** - Copy the annotated PNG to the clipboard in one step
- **Save to Folder & Copy Path** - Optionally save annotated screenshots to a custom folder and copy the file path
- **Custom Save Location** - Choose where your screenshots are saved
- **Launch at Login** - Registers the installed app as an enabled macOS Login Item

## Requirements

- macOS 15.0 or later
- Xcode 15.0 or later

## Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Wirenut33/quick-shot.git
   cd quick-shot
   ```

2. Open the project in Xcode:
   ```bash
   open QuickShot.xcodeproj
   ```

3. Disable App Sandbox (required for screenshot functionality):
   - Select the project in Xcode
   - Go to **Signing & Capabilities** tab
   - Remove or disable **App Sandbox**

4. Build and run the project (⌘R), or build a Release app and copy it to `/Applications`

5. Grant screen recording permission when prompted (required for screenshot functionality)

## Usage

Once running, QuickShot appears as a camera icon in your menu bar. Click it to access:

- **Capture Full Screen** - Takes a screenshot of the entire screen
- **Capture Selection** - Lets you draw a rectangle to capture
- **Capture Window** - Captures the window you click
- **Annotate Before Copying** - Opens the editor when enabled; copies the screenshot directly to the clipboard when disabled
- **Save to Folder & Copy Path** - Controls whether saving from the editor also copies the saved PNG path
- **Save Location** - Click to choose a custom save folder (defaults to Desktop)
- **Launch at Login** - Enable or disable automatic launch from the menu

In the editor, choose Rectangle, Arrow, or Text. All markup is red. Add an optional description, then use **Copy & Close** or **Save PNG**.

## Permissions

QuickShot requires **Screen & System Audio Recording** permission to function. Allow it when macOS asks, or enable it manually in:

**System Settings > Privacy & Security > Screen & System Audio Recording > QuickShot**

QuickShot attempts a capture before diagnosing a permission problem, so an outdated permission preflight result cannot block it. If an enabled permission stops working after replacing the app, quit and reopen QuickShot. To preserve permissions reliably across builds, sign each release with the same Apple Development or Developer ID identity; macOS treats ad-hoc signed rebuilds as different code.

## Author

Michael Morale

## License

MIT License

## Collect several snapshots (1.3)

1. Turn on **Collect Snapshots** in the camera menu. The count appears beside the camera.
2. Use Capture Selection, Capture Window, or Capture Full Screen repeatedly. Each capture saves immediately without opening the editor or changing your clipboard.
3. Open **Snapshot Collection**, select the examples you want (⌘-click / Shift-click, or Select All), and choose **Copy Selected**.
4. Switch to Codex or another app and press **⌘V**. QuickShot supplies separate PNG/file attachments. Apps decide how many clipboard items they accept; use **Copy as One Image** for a single combined image when needed. Large combined images are scaled to bounded dimensions.

**Copy All Snapshots** is also available directly in the menu. Snapshots remain in `~/Library/Application Support/QuickShot/Snapshots` across restarts until you remove them (to Trash). **Show Folder** opens the PNG files in Finder for dragging or attaching. Turn off Collect Snapshots to return to your existing annotation/clipboard flow.

Use **Annotate** in the collection to edit an example, then **Add to Collection** in the editor to save the annotated version as a new snapshot. The original remains available.

### Collection validation

```sh
xcrun swiftc -module-cache-path .build/SwiftModuleCache QuickShot/SnapshotCollection.swift Tests/CollectionTests.swift -o .build/collection-tests
.build/collection-tests
```

Run tests with normal macOS pasteboard access. The tests use a private pasteboard and temporary images. For installed-app capture validation, launch with `--collection-capture-test`; it captures the screen, verifies two persistent images and two private clipboard attachments, opens a diagnostic collection, and writes `QuickShot-collection-test.txt` in the app's temporary directory.
