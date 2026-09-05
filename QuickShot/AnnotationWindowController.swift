//
//  AnnotationWindowController.swift
//  QuickShot
//

import AppKit
import SwiftUI

final class AnnotationWindowController: NSWindowController, NSWindowDelegate {
    private let editorDocument: AnnotationDocument
    var onClose: (() -> Void)?

    init(image: NSImage, screenshotManager: ScreenshotManager, collection: SnapshotCollection) {
        let document = AnnotationDocument(image: image)
        self.editorDocument = document

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_120, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickShot — Annotate"
        window.minSize = NSSize(width: 1040, height: 620)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: AnnotationEditorView(
                document: document,
                screenshotManager: screenshotManager,
                collection: collection,
                closeWindow: { [weak window] in window?.performClose(nil) }
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
}
