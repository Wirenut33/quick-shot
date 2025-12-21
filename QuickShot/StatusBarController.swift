//
//  StatusBarController.swift
//  QuickShot
//

import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var screenshotManager = ScreenshotManager()
    private var copyPathToggle: NSMenuItem!
    private var saveLocationItem: NSMenuItem!

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "QuickShot")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }

        statusItem.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        let fullScreenItem = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        fullScreenItem.target = self
        menu.addItem(fullScreenItem)

        let selectionItem = NSMenuItem(title: "Capture Selection", action: #selector(captureSelection), keyEquivalent: "")
        selectionItem.target = self
        menu.addItem(selectionItem)

        let windowItem = NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "")
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        copyPathToggle = NSMenuItem(title: "Save to Folder & Copy Path", action: #selector(toggleCopyPathMode), keyEquivalent: "")
        copyPathToggle.target = self
        copyPathToggle.state = screenshotManager.copyPathMode ? .on : .off
        menu.addItem(copyPathToggle)

        saveLocationItem = NSMenuItem(title: "Save Location: \(screenshotManager.saveLocationName)", action: #selector(chooseSaveLocation), keyEquivalent: "")
        saveLocationItem.target = self
        menu.addItem(saveLocationItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit QuickShot", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleCopyPathMode() {
        let newValue = !screenshotManager.copyPathMode
        screenshotManager.copyPathMode = newValue
        copyPathToggle.state = newValue ? .on : .off
    }

    @objc private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose where to save screenshots"

        if panel.runModal() == .OK, let url = panel.url {
            screenshotManager.saveLocation = url
            saveLocationItem.title = "Save Location: \(screenshotManager.saveLocationName)"
        }
    }

    @objc private func captureFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.screenshotManager.captureFullScreen()
        }
    }

    @objc private func captureSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.screenshotManager.captureSelection()
        }
    }

    @objc private func captureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.screenshotManager.captureWindow()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
