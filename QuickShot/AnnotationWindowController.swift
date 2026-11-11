//
//  AnnotationWindowController.swift
//  QuickShot
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AnnotationWindowController: NSWindowController, NSWindowDelegate {
    private let editorDocument: AnnotationDocument
    private let settings: AppSettings
    private let collection: SnapshotCollection
    private var discardConfirmationExpires: Date?
    var onClose: (() -> Void)?

    init(image: NSImage, settings: AppSettings, collection: SnapshotCollection) {
        let document = AnnotationDocument(image: image)
        self.editorDocument = document
        self.settings = settings
        self.collection = collection

        for (name, style) in settings.toolStyles() {
            if let tool = AnnotationTool(rawValue: name) { document.toolStyles[tool] = style }
        }
        document.style = document.style(for: document.selectedTool)
        document.onToolStyleChange = { [weak settings] tool, style in
            settings?.setToolStyle(style, for: tool.rawValue)
        }

        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: min(1_120, visible.width - 40), height: min(800, visible.height - 60)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickShot — Annotate"
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        document.onKeyCommand = { [weak self] command in self?.perform(command) }
        window.contentView = NSHostingView(
            rootView: AnnotationEditorView(
                document: document,
                settings: settings,
                commands: EditorCommands(
                    copyAndClose: { [weak self] in self?.copyAndClose() },
                    save: { [weak self] askWhere in self?.save(askWhere: askWhere) },
                    addToCollection: { [weak self] in self?.addToCollection() },
                    copyText: { [weak self] in self?.copyText() },
                    close: { [weak self] in self?.window?.performClose(nil) }
                )
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }

    // MARK: Commands

    private func perform(_ command: EditorKeyCommand) {
        switch command {
        case .save: save(askWhere: false)
        case .saveAs: save(askWhere: true)
        case .copy: copyImage()
        case .escape: handleEscape()
        }
    }

    /// Escape closes at once only when nothing would be lost. Otherwise it asks for a
    /// second press, so a reflex Escape after deselecting cannot throw markup away.
    private func handleEscape() {
        if !editorDocument.hasUnsavedChanges {
            window?.performClose(nil)
        } else if let expires = discardConfirmationExpires, expires > Date() {
            window?.performClose(nil)
        } else {
            discardConfirmationExpires = Date().addingTimeInterval(4)
            editorDocument.statusMessage = "Unsaved markup. Press Esc again to discard it, or ⌘↩ to copy."
        }
    }

    private func copyImage() {
        if editorDocument.copyToClipboard() {
            HUD.show("Copied to clipboard")
        }
    }

    private func copyAndClose() {
        if editorDocument.copyToClipboard() {
            HUD.show("Copied to clipboard")
            window?.performClose(nil)
        }
    }

    private func addToCollection() {
        if let image = editorDocument.renderedImage(), collection.add(image) {
            editorDocument.markClean()
            HUD.show("Added to collection (\(collection.snapshots.count))", symbol: "photo.stack")
            window?.performClose(nil)
        } else {
            editorDocument.statusMessage = collection.message
        }
    }

    /// Saves to the chosen folder in one step. Without a folder, or when asked to, it
    /// shows a save panel. A quick save never replaces an existing file.
    private func save(askWhere: Bool) {
        let base = AppSettings.screenshotBaseName()
        if !askWhere {
            let quickSaved = settings.withSaveFolder { folder in
                editorDocument.save(
                    to: AppSettings.uniqueFileURL(in: folder, base: base),
                    copyPath: settings.copyPathMode,
                    overwrite: false
                )
            }
            if quickSaved == true {
                HUD.show(settings.copyPathMode ? "Saved, path copied" : "Saved to \(settings.saveFolderName ?? "folder")",
                         symbol: "square.and.arrow.down.fill")
                return
            }
        }

        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolderURL
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = "\(base).png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if self.editorDocument.save(to: url, copyPath: self.settings.copyPathMode) {
                HUD.show(self.settings.copyPathMode ? "Saved, path copied" : "Saved \(url.lastPathComponent)",
                         symbol: "square.and.arrow.down.fill")
            }
        }
    }

    /// Reads the text in the image as it will be exported, so anything redacted stays out.
    private func copyText() {
        guard let rendered = editorDocument.renderedImage(),
              let image = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            editorDocument.statusMessage = "QuickShot could not read this image."
            return
        }
        editorDocument.statusMessage = "Reading text…"
        Task { @MainActor [weak self] in
            let result = try? await TextRecognizer.recognizeInBackground(image)
            guard let self else { return }
            guard let text = result, !text.isEmpty else {
                self.editorDocument.statusMessage = "No text found in this image."
                HUD.show("No text found", symbol: "text.magnifyingglass")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.editorDocument.statusMessage = "Text copied."
            HUD.show("Copied text: \(StatusBarController.preview(of: text))", symbol: "text.viewfinder")
        }
    }
}
