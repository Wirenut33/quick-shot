# QuickShot

A lightweight macOS menu bar app for quick screenshots.

## Features

- **Capture Full Screen** - Capture your entire screen
- **Capture Selection** - Draw a region to capture
- **Capture Window** - Click on a window to capture it
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

3. Build and run the project (⌘R)

4. Grant screen recording permission when prompted (required for screenshot functionality)

## Usage

Once running, QuickShot appears as a camera icon in your menu bar. Click it to access:

- **Capture Full Screen** - Takes a screenshot of the entire screen
- **Capture Selection** - Lets you draw a rectangle to capture
- **Capture Window** - Click any window to capture it
- **Save to Folder & Copy Path** - Toggle to save files and copy path instead of copying image to clipboard
- **Save Location** - Click to choose a custom save folder (defaults to Desktop)

## Permissions

QuickShot requires **Screen Recording** permission to function. macOS will prompt you to grant this permission on first use. You can also enable it manually in:

**System Settings > Privacy & Security > Screen Recording > QuickShot**

## License

MIT License
