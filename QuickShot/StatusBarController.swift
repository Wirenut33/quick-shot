//
//  StatusBarController.swift
//  QuickShot
//

import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var canInstallUpdate: Bool {
        !isCapturing && annotationWindows.isEmpty && NSApp.modalWindow == nil && !isMenuOpen
            && welcomeWindow?.window?.isVisible != true
    }

    private let statusItem: NSStatusItem
    private let settings = AppSettings.shared
    private let screenshotManager = ScreenshotManager()
    private let collection = SnapshotCollection()
    private let loginItemManager = LoginItemManager.shared
    private var collectionWindow: SnapshotCollectionWindowController?
    private var settingsWindow: HostedWindowController?
    private var welcomeWindow: HostedWindowController?
    private var annotationWindows: [AnnotationWindowController] = []
    private var isCapturing = false
    private var isMenuOpen = false
    private var isRecordingShortcut = false
    private var iconReset: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []

    private var captureItems: [CaptureAction: NSMenuItem] = [:]
    private var collectionToggle: NSMenuItem!
    private var collectionItem: NSMenuItem!
    private var copyCollectionItem: NSMenuItem!
    private var annotationToggle: NSMenuItem!
    private var permissionItem: NSMenuItem!
    #if !APPSTORE
    private var updateItem: NSMenuItem!
    #endif

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setStatusIcon(symbolName: "camera.viewfinder", description: "QuickShot")
        statusItem.menu = createMenu()
        statusItem.menu?.delegate = self
        collection.onChange = { [weak self] in self?.refreshMenuState() }
        AppCommands.showWelcome = { [weak self] in self?.showWelcome() }

        // Published values change after these fire, so read them on the next turn.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenuState() }
            .store(in: &observers)
        settings.$shortcuts.combineLatest(settings.$welcomeCompleted)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyShortcuts() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: .shortcutRecordingChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.isRecordingShortcut = (note.object as? Bool) == true
                self?.applyShortcuts()
            }
            .store(in: &observers)
        applyShortcuts()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshMenuState()
    }

    func menuDidClose(_ menu: NSMenu) { isMenuOpen = false }

    // MARK: Menu

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let selectors: [CaptureAction: Selector] = [
            .fullScreen: #selector(captureFullScreen),
            .selection: #selector(captureSelection),
            .window: #selector(captureWindow),
            .text: #selector(captureText)
        ]
        for action in CaptureAction.allCases {
            guard let selector = selectors[action] else { continue }
            let item = menuItem(title: action.title, action: selector)
            captureItems[action] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())
        collectionToggle = menuItem(title: "Collect Snapshots", action: #selector(toggleCollection))
        menu.addItem(collectionToggle)
        collectionItem = menuItem(title: "Snapshot Collection…", action: #selector(showCollection))
        menu.addItem(collectionItem)
        copyCollectionItem = menuItem(title: "Copy All Snapshots", action: #selector(copyCollection))
        menu.addItem(copyCollectionItem)

        menu.addItem(.separator())
        annotationToggle = menuItem(title: "Annotate Before Copying", action: #selector(toggleAnnotationMode))
        menu.addItem(annotationToggle)

        menu.addItem(.separator())
        permissionItem = menuItem(title: "Allow Screen Recording…", action: #selector(openScreenRecordingSettings))
        menu.addItem(permissionItem)
        menu.addItem(menuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        #if !APPSTORE
        updateItem = menuItem(title: "Check for Updates…", action: #selector(checkForUpdates))
        menu.addItem(updateItem)
        #endif

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit QuickShot", action: #selector(quitApp), keyEquivalent: "q"))

        refreshMenuState()
        return menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshMenuState() {
        #if !APPSTORE
        updateItem?.isEnabled = AppUpdater.shared.canCheckForUpdates
        #endif
        for (action, item) in captureItems {
            item.isEnabled = !isCapturing
            // Show the global shortcut once it is active; otherwise leave the item bare.
            if settings.welcomeCompleted, let shortcut = settings.shortcut(for: action),
               !settings.unavailableShortcuts.contains(action), let key = shortcut.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = shortcut.modifierFlags
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
        collectionToggle?.state = settings.collectMode ? .on : .off
        collectionItem?.title = "Snapshot Collection (\(collection.snapshots.count))…"
        copyCollectionItem?.isEnabled = !collection.snapshots.isEmpty
        statusItem.button?.title = settings.collectMode ? " \(collection.snapshots.count)" : ""
        annotationToggle?.state = settings.annotateMode ? .on : .off
        permissionItem?.isHidden = screenshotManager.hasScreenRecordingPermission()
    }

    // MARK: Shortcuts

    /// Global shortcuts become active only after the welcome window has shown them and
    /// the user has continued, and they pause while a recorder is listening.
    private func applyShortcuts() {
        HotKeyCenter.shared.unregisterAll()
        var unavailable: Set<CaptureAction> = []
        if settings.welcomeCompleted, !isRecordingShortcut {
            for (action, shortcut) in settings.shortcuts {
                let registered = HotKeyCenter.shared.register(id: action.hotKeyID, shortcut: shortcut) { [weak self] in
                    self?.capture(action, afterMenu: false)
                }
                if !registered { unavailable.insert(action) }
            }
        }
        if settings.unavailableShortcuts != unavailable, !isRecordingShortcut {
            settings.unavailableShortcuts = unavailable
        }
        refreshMenuState()
    }

    // MARK: Windows

    func showWelcomeIfNeeded() {
        if !settings.welcomeCompleted { showWelcome() }
    }

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let controller = HostedWindowController(
                title: "Welcome to QuickShot",
                content: WelcomeView { [weak self] in self?.welcomeWindow?.close() }
            )
            controller.onClose = { [weak self] in self?.welcomeWindow = nil }
            welcomeWindow = controller
        }
        welcomeWindow?.present()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = HostedWindowController(
                title: "QuickShot Settings",
                content: SettingsView()
            )
        }
        settingsWindow?.present()
    }

    @objc private func showCollection() {
        if collectionWindow == nil {
            collectionWindow = SnapshotCollectionWindowController(collection: collection) { [weak self] image in
                self?.openEditor(for: image)
            }
        }
        collectionWindow?.present()
    }

    private func openEditor(for image: NSImage) {
        let controller = AnnotationWindowController(image: image, settings: settings, collection: collection)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.annotationWindows.removeAll { $0 === controller }
        }
        annotationWindows.append(controller)
        controller.present()
    }

    // MARK: Menu actions

    #if !APPSTORE
    @objc private func checkForUpdates() { AppUpdater.shared.checkForUpdates() }
    #endif

    @objc private func toggleCollection() {
        settings.collectMode.toggle()
        refreshMenuState()
    }

    @objc private func copyCollection() {
        if collection.copy(collection.snapshots) {
            confirm("Copied \(collection.snapshots.count) snapshots")
        } else {
            showAlert(title: "Copy Failed", message: collection.message)
        }
    }

    @objc private func toggleAnnotationMode() {
        settings.annotateMode.toggle()
        refreshMenuState()
    }

    @objc private func captureFullScreen() { capture(.fullScreen, afterMenu: true) }
    @objc private func captureSelection() { capture(.selection, afterMenu: true) }
    @objc private func captureWindow() { capture(.window, afterMenu: true) }
    @objc private func captureText() { capture(.text, afterMenu: true) }

    // MARK: Capture

    private func capture(_ action: CaptureAction, afterMenu: Bool) {
        // A shortcut pressed twice, or pressed while the menu item is also firing, must
        // start only one capture.
        guard !isCapturing else { return }
        isCapturing = true
        refreshMenuState()
        collectionWindow?.window?.orderOut(nil)
        HUD.dismiss()
        Task { @MainActor [weak self] in
            // Let the menu finish closing so it is not part of the frozen frame.
            if afterMenu { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard let self else { return }
            let result: Result<CaptureOutput, Error>
            do {
                result = .success(try await self.screenshotManager.capture(action))
            } catch {
                result = .failure(error)
            }
            self.isCapturing = false
            self.refreshMenuState()
            self.handle(result)
        }
    }

    private func handle(_ result: Result<CaptureOutput, Error>) {
        switch result {
        case .success(.image(let image)):
            // An enabled annotation preference also applies while collecting.
            if settings.annotateMode {
                openEditor(for: image)
            } else if settings.collectMode {
                if collection.add(image) {
                    confirm("Added to collection (\(collection.snapshots.count))", symbol: "photo.stack")
                } else {
                    showAlert(title: "Save Failed", message: collection.message)
                }
            } else if screenshotManager.copyToClipboard(image) {
                confirm("Copied to clipboard")
            } else {
                showAlert(title: "Copy Failed", message: "QuickShot captured the screen but could not copy the image.")
            }
        case .success(.text(let text)):
            // An empty result must not look like a successful copy; the clipboard is untouched.
            if text.isEmpty {
                HUD.show("No text found", symbol: "text.magnifyingglass")
            } else if screenshotManager.copyToClipboard(text) {
                confirm("Copied text: \(Self.preview(of: text))", symbol: "text.viewfinder")
            } else {
                showAlert(title: "Copy Failed", message: "QuickShot read the text but could not copy it.")
            }
        case .failure(ScreenshotError.cancelled):
            return
        case .failure(ScreenshotError.permissionRequired):
            showScreenRecordingFailure()
        case .failure(let error):
            showAlert(title: "Capture Failed", message: error.localizedDescription)
        }
    }

    static func preview(of text: String, limit: Int = 36) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    private func showScreenRecordingFailure() {
        // The first capture makes macOS show its own permission prompt. A modal alert
        // here would cover it, so the failure is shown without taking focus.
        flashStatusIcon(symbolName: "exclamationmark.triangle.fill", description: "Screen Recording access blocked",
                        toolTip: "Allow QuickShot in Screen Recording settings, then reopen QuickShot.", duration: 8)
        HUD.show("Screen Recording access is needed", symbol: "exclamationmark.triangle.fill")
        if !settings.welcomeCompleted { showWelcome() }
    }

    private func confirm(_ message: String, symbol: String = "checkmark.circle.fill") {
        flashStatusIcon(symbolName: "checkmark.circle.fill", description: message, toolTip: message, duration: 1.2)
        HUD.show(message, symbol: symbol)
    }

    private func flashStatusIcon(symbolName: String, description: String, toolTip: String, duration: TimeInterval) {
        iconReset?.cancel()
        setStatusIcon(symbolName: symbolName, description: description)
        statusItem.button?.toolTip = toolTip
        let reset = DispatchWorkItem { [weak self] in
            self?.setStatusIcon(symbolName: "camera.viewfinder", description: "QuickShot")
            self?.statusItem.button?.toolTip = nil
        }
        iconReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: reset)
    }

    private func setStatusIcon(symbolName: String, description: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
    }

    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
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

    // MARK: Diagnostics

    #if !APPSTORE
    // Explicit diagnostic launch only: exercise actual capture, durable storage, and
    // multi-item pasteboard serialization without replacing the user's clipboard.
    func testCollectionCapture() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-Capture-Test-\(UUID().uuidString)")
        let testCollection = SnapshotCollection(directory: folder)
        Task { @MainActor [weak self] in
            guard let self else { return }
            var report = "FAIL: capture"
            do {
                guard case .image(let image) = try await self.screenshotManager.capture(.fullScreen) else {
                    throw ScreenshotError.invalidImage
                }
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
            } catch {
                report = "FAIL: \(error.localizedDescription)"
            }
            try? report.write(
                to: FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-collection-test.txt"),
                atomically: true, encoding: .utf8
            )
        }
    }

    func captureForTesting(_ action: CaptureAction) {
        capture(action, afterMenu: false)
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
    #endif

    #if DEBUG
    func showSettingsForTesting() { showSettings() }

    /// Development builds only: captures every display through the real engine, checks
    /// that each frame's pixel size matches its display, and writes a report.
    func runCaptureSelfTest() {
        Task { @MainActor in
            var lines: [String] = []
            do {
                // Asking ScreenCaptureKit without permission would raise the system prompt.
                guard CGPreflightScreenCaptureAccess() else {
                    throw ScreenshotError.captureFailed("SKIP: Screen Recording is not granted to this build")
                }
                let content = try await CaptureEngine.shareableContent()
                for capture in try await CaptureEngine.captureAll(content.displays) {
                    let mode = CGDisplayCopyDisplayMode(capture.displayID)
                    let expected = "\(mode?.pixelWidth ?? 0)x\(mode?.pixelHeight ?? 0)"
                    let actual = "\(capture.image.width)x\(capture.image.height)"
                    lines.append("\(actual == expected ? "PASS" : "FAIL"): display \(capture.displayID) captured \(actual), expected \(expected), frame \(capture.frame)")
                }
                lines.append("INFO: \(CaptureEngine.windowCandidates(in: content).count) window candidates")
                if lines.isEmpty { lines.append("FAIL: no displays") }
            } catch {
                let detail = error.localizedDescription
                lines.append(detail.hasPrefix("SKIP") ? detail : "FAIL: \(detail)")
            }
            try? lines.joined(separator: "\n").write(
                to: FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-capture-self-test.txt"),
                atomically: true, encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }
    #endif
}
