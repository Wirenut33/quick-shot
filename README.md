# QuickShot

A lightweight macOS menu bar app for quick screenshots.

## Features

- **Capture Full Screen** - Capture your entire screen
- **Capture Selection** - Draw a region to capture
- **Capture Window** - Click on a window to capture it
- **Annotate After Capture** - Open each screenshot in a simple Excalidraw-style editor: draw red rectangles, arrows, and text, expand the canvas, add a written description, then copy the result with one click
- **Save to Folder & Copy Path** - Optionally save screenshots to a custom folder and copy the file path to clipboard
- **Custom Save Location** - Choose where your screenshots are saved

## Requirements

- macOS 13.0 or later
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

4. Build and run the project (⌘R)

5. Grant screen recording permission when prompted (required for screenshot functionality)

## Usage

Once running, QuickShot appears as a camera icon in your menu bar. Click it to access:

- **Capture Full Screen** - Takes a screenshot of the entire screen
- **Capture Selection** - Lets you draw a rectangle to capture
- **Capture Window** - Click any window to capture it
- **Annotate After Capture** - Toggle to open every capture in the annotation editor before it is copied or saved
- **Save to Folder & Copy Path** - Toggle to save files and copy path instead of copying image to clipboard
- **Save Location** - Click to choose a custom save folder (defaults to Desktop)

### Annotation editor

With **Annotate After Capture** on, each screenshot opens in an editor window:

- **Tools** - Select/Move (`V`), Rectangle (`R`), Arrow (`A`), Text (`T`). Drag to draw a rectangle or arrow; click to place text. Everything is drawn in red.
- **Select** - Click a mark to select it, drag to move it, press `⌫` to delete it. Double-click a text label to edit it. `⌘Z` undoes.
- **Expand canvas** - Adds white space around the screenshot so you can draw or write outside the captured area.
- **Description** - Type in the box at the bottom; the text is rendered in a band below the screenshot, so it travels with the image when you paste it into a chat or a coding assistant.
- **Copy to Clipboard** (`⌘↩`) - Copies the finished image so you can paste it anywhere. With **Save to Folder & Copy Path** on, the button becomes **Save & Copy Path** and behaves like a normal capture in that mode. **Cancel** (`⌘W`) discards the edit.

## Permissions

QuickShot requires **Screen Recording** permission to function. macOS will prompt you to grant this permission on first use. You can also enable it manually in:

**System Settings > Privacy & Security > Screen Recording > QuickShot**

## Author

Michael Morale

## License

MIT License
