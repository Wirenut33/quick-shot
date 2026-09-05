//
//  StatusBarController.swift
//  QuickShot
//

import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    var canInstallUpdate: Bool { !isCapturing && annotationWindows.isEmpty && NSApp.modalWindow == nil && !isMenuOpen }
    private let statusItem: NSStatusItem
    private let screenshotManager = ScreenshotManager()
    private let collection = SnapshotCollection()
    private var collectionWindow: SnapshotCollectionWindowController?
    private var collectionToggle: NSMenuItem!
    private var collectionItem: NSMenuItem!
    private var copyCollectionItem: NSMenuItem!
    private var isCapturing = false
    private var isMenuOpen = false
    private var collectMode: Bool {
        get { UserDefaults.standard.bool(forKey: "collectSnapshots") }
        set { UserDefaults.standard.set(newValue, forKey: "collectSnapshots") }
    }
    private let loginItemManager = LoginItemManager.shared
    private var annotationWindows: [AnnotationWindowController] = []
    private var permissionIndicatorReset: DispatchWorkItem?

    private var captureItems: [NSMenuItem] = []
    private var annotationToggle: NSMenuItem!
    private var copyPathToggle: NSMenuItem!
    private var saveLocationItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var automaticUpdateItem: NSMenuItem!

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setStatusIcon(symbolName: "camera.viewfinder", description: "QuickShot")

        statusItem.menu = createMenu()
        statusItem.menu?.delegate = self
        collection.onChange = { [weak self] in self?.refreshMenuState() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshMenuState()
    }

    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let fullScreenItem = menuItem(
            title: "Capture Full Screen",
            action: #selector(captureFullScreen),
            keyEquivalent: "1"
        )
        let selectionItem = menuItem(
            title: "Capture Selection",
            action: #selector(captureSelection),
            keyEquivalent: "2"
        )
        let windowItem = menuItem(
            title: "Capture Window",
            action: #selector(captureWindow),
            keyEquivalent: "3"
        )
        captureItems = [fullScreenItem, selectionItem, windowItem]
        captureItems.forEach(menu.addItem)

        menu.addItem(.separator())

        collectionToggle = menuItem(title: "Collect Snapshots", action: #selector(toggleCollection))
        menu.addItem(collectionToggle)
        collectionItem = menuItem(title: "Snapshot Collection…", action: #selector(showCollection), keyEquivalent: "4")
        menu.addItem(collectionItem)
        copyCollectionItem = menuItem(title: "Copy All Snapshots", action: #selector(copyCollection))
        menu.addItem(copyCollectionItem)
        menu.addItem(.separator())

        annotationToggle = menuItem(
            title: "Annotate Before Copying",
            action: #selector(toggleAnnotationMode)
        )
        menu.addItem(annotationToggle)

        copyPathToggle = menuItem(
            title: "Save to Folder & Copy Path",
            action: #selector(toggleCopyPathMode)
        )
        menu.addItem(copyPathToggle)

        saveLocationItem = menuItem(
            title: "Save Location: \(screenshotManager.saveLocationName)",
            action: #selector(chooseSaveLocation)
        )
        menu.addItem(saveLocationItem)

        menu.addItem(.separator())

        launchAtLoginItem = menuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin)
        )
        menu.addItem(launchAtLoginItem)

        let screenPermissionItem = menuItem(
            title: "Screen Recording Settings…",
            action: #selector(openScreenRecordingSettings)
        )
        menu.addItem(screenPermissionItem)

        menu.addItem(.separator())
        updateItem = menuItem(title: "Check for Updates…", action: #selector(checkForUpdates))
        menu.addItem(updateItem)
        automaticUpdateItem = menuItem(title: "Automatic Updates", action: #selector(toggleAutomaticUpdates))
        menu.addItem(automaticUpdateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit QuickShot", action: #selector(quitApp), keyEquivalent: "q"))

        refreshMenuState()
        return menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshMenuState() {
        updateItem?.isEnabled = AppUpdater.shared.canCheckForUpdates
        automaticUpdateItem?.state = AppUpdater.shared.automaticUpdates ? .on : .off
        collectionToggle?.state = collectMode ? .on : .off
        collectionItem?.title = "Snapshot Collection (\(collection.snapshots.count))…"
        copyCollectionItem?.isEnabled = !collection.snapshots.isEmpty
        statusItem.button?.title = collectMode ? " \(collection.snapshots.count)" : ""
        captureItems.forEach { $0.isEnabled = !isCapturing }
        annotationToggle?.state = screenshotManager.annotateMode ? .on : .off
        copyPathToggle?.state = screenshotManager.copyPathMode ? .on : .off
        copyPathToggle?.isEnabled = screenshotManager.annotateMode
        saveLocationItem?.title = "Save Location: \(screenshotManager.saveLocationName)"
        saveLocationItem?.isEnabled = screenshotManager.annotateMode
        launchAtLoginItem?.state = loginItemManager.isEnabled ? .on : .off
        launchAtLoginItem?.title = loginItemManager.requiresApproval
            ? "Launch at Login (Approval Required)"
            : "Launch at Login"
    }

    @objc private func checkForUpdates() { AppUpdater.shared.checkForUpdates() }

    @objc private func toggleAutomaticUpdates() {
        AppUpdater.shared.automaticUpdates.toggle()
        refreshMenuState()
    }

    @objc private func toggleCollection() {
        collectMode.toggle()
        refreshMenuState()
    }

    @objc private func showCollection() {
        if collectionWindow == nil {
            collectionWindow = SnapshotCollectionWindowController(collection: collection) { [weak self] image in
                self?.openEditor(for: image)
            }
        }
        collectionWindow?.present()
    }

    @objc private func copyCollection() {
        if collection.copy(collection.snapshots) { showCopyConfirmation() }
        else { showAlert(title: "Copy Failed", message: collection.message) }
    }

    @objc private func toggleAnnotationMode() {
        screenshotManager.annotateMode.toggle()
        refreshMenuState()
    }

    @objc private func toggleCopyPathMode() {
        screenshotManager.copyPathMode.toggle()
        refreshMenuState()
    }

    @objc private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose where to save annotated screenshots"

        if panel.runModal() == .OK, let url = panel.url {
            screenshotManager.saveLocation = url
            refreshMenuState()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
            refreshMenuState()
            if loginItemManager.requiresApproval {
                showAlert(
                    title: "Approve QuickShot",
                    message: "macOS needs your approval in System Settings > General > Login Items."
                )
            }
        } catch {
            showAlert(title: "Could Not Update Login Item", message: error.localizedDescription)
        }
    }

    @objc private func captureFullScreen() {
        capture(.fullScreen)
    }

    @objc private func captureSelection() {
        capture(.selection)
    }

    @objc private func captureWindow() {
        capture(.window)
    }

    // Explicit diagnostic launch only: exercise actual capture, durable storage, and
    // multi-item pasteboard serialization without replacing the user's clipboard.
    func testCollectionCapture() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-Capture-Test-\(UUID().uuidString)")
        let testCollection = SnapshotCollection(directory: folder)
        screenshotManager.capture(.fullScreen) { [weak self] result in
            guard let self else { return }
            var report = "FAIL: capture"
            if case .success(let image) = result {
                let board = NSPasteboard.withUniqueName()
                let saved = testCollection.add(image) && testCollection.add(image)
                let restored = SnapshotCollection(directory: folder)
                let copied = restored.copy(restored.snapshots, to: board)
                report = saved && copied && board.pasteboardItems?.count == 2
                    ? "PASS: real capture, two saved snapshots, reload, two clipboard attachments"
                    : "FAIL: collection or clipboard"
                board.releaseGlobally()
                self.collectionWindow = SnapshotCollectionWindowController(collection: testCollection) { [weak self] image in
                    self?.openEditor(for: image)
                }
                self.collectionWindow?.present()
            } else if case .failure(let error) = result {
                report = "FAIL: \(error.localizedDescription)"
            }
            try? report.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-collection-test.txt"), atomically: true, encoding: .utf8)
        }
    }

    func captureForTesting(_ mode: CaptureMode) {
        capture(mode)
    }

    func openEditorForTesting() {
        let size = NSSize(width: 1_000, height: 620)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let title = "QuickShot annotation smoke test" as NSString
        title.draw(
            at: CGPoint(x: 70, y: 310),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        image.unlockFocus()
        openEditor(for: image)
    }

    private func capture(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        isCapturing = true
        captureItems.forEach { $0.isEnabled = false }
        collectionWindow?.window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.screenshotManager.capture(mode) { [weak self] result in
                guard let self else { return }
                self.isCapturing = false
                self.captureItems.forEach { $0.isEnabled = true }

                switch result {
                case .success(let image):
                    // An enabled annotation preference must also apply in collection mode.
                    if self.screenshotManager.annotateMode {
                        self.openEditor(for: image)
                    } else if self.collectMode {
                        if self.collection.add(image) {
                            self.setStatusIcon(symbolName: "photo.stack", description: "Snapshot saved to collection")
                            self.statusItem.button?.toolTip = self.collection.message
                        } else {
                            self.showAlert(title: "Save Failed", message: self.collection.message)
                        }
                    } else if self.screenshotManager.copyToClipboard(image) {
                        self.showCopyConfirmation()
                    } else {
                        self.showAlert(
                            title: "Copy Failed",
                            message: "QuickShot captured the screen but could not copy the image."
                        )
                    }
                case .failure(let error as ScreenshotError):
                    if case .cancelled = error {
                        return
                    } else if case .permissionRequired = error {
                        self.showScreenRecordingFailure()
                    } else {
                        self.showAlert(title: "Capture Failed", message: error.localizedDescription)
                    }
                case .failure(let error):
                    self.showAlert(title: "Capture Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func openEditor(for image: NSImage) {
        let controller = AnnotationWindowController(
            image: image,
            screenshotManager: screenshotManager,
            collection: collection
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.annotationWindows.removeAll { $0 === controller }
        }
        annotationWindows.append(controller)
        controller.present()
    }

    private func showScreenRecordingFailure() {
        // screencapture presents macOS's native permission UI. A modal alert
        // here would cover that prompt and make it look as though QuickShot
        // were asking for the same approval twice. Keep the failure visible in
        // the menu bar without competing with the system dialog.
        permissionIndicatorReset?.cancel()
        setStatusIcon(
            symbolName: "exclamationmark.triangle.fill",
            description: "Screen Recording access blocked"
        )
        statusItem.button?.toolTip = "Allow QuickShot in Screen Recording settings, then reopen QuickShot."

        let reset = DispatchWorkItem { [weak self] in
            self?.setStatusIcon(symbolName: "camera.viewfinder", description: "QuickShot")
            self?.statusItem.button?.toolTip = nil
        }
        permissionIndicatorReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: reset)
    }

    private func showCopyConfirmation() {
        setStatusIcon(symbolName: "checkmark.circle.fill", description: "Screenshot copied")
        statusItem.button?.toolTip = "Screenshot copied to the clipboard"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.setStatusIcon(symbolName: "camera.viewfinder", description: "QuickShot")
            self?.statusItem.button?.toolTip = nil
        }
    }

    private func setStatusIcon(symbolName: String, description: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
