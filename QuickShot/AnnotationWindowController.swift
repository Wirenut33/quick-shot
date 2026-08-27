//
//  AnnotationWindowController.swift
//  QuickShot
//

import AppKit
import SwiftUI

/// Owns the single annotation editor window. Presenting a new capture replaces any open editor.
@MainActor
final class AnnotationWindowController: NSObject, NSWindowDelegate {
    static let shared = AnnotationWindowController()

    private var window: NSWindow?
    private var document: AnnotationDocument?
    private var onFinish: ((NSImage) -> Void)?

    func present(image: NSImage, finishTitle: String, onFinish: @escaping (NSImage) -> Void) {
        window?.close()

        let document = AnnotationDocument(image: image)
        self.document = document
        self.onFinish = onFinish

        let editor = AnnotationEditorView(
            document: document,
            finishTitle: finishTitle,
            onFinish: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.window?.close() }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.title = "Annotate Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 700, height: 500)
        window.setContentSize(initialSize(for: image))
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func initialSize(for image: NSImage) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = min(image.size.width + 80, screen.width * 0.9)
        let height = min(image.size.height + 230, screen.height * 0.9)
        return NSSize(width: max(width, 760), height: max(height, 560))
    }

    private func finish() {
        guard let document else { return }
        document.finishTextEditing()
        document.selectedID = nil
        if let rendered = AnnotationExporter.render(document) {
            onFinish?(rendered)
        }
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        document = nil
        onFinish = nil
    }
}

enum AnnotationExporter {
    /// Renders the document exactly as the editor draws it, at the screenshot's native pixel density.
    @MainActor
    static func render(_ document: AnnotationDocument) -> NSImage? {
        let size = document.canvasSize
        let content = Canvas { context, _ in
            document.draw(in: &context, showSelection: false)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = document.pixelScale
        guard let cgImage = renderer.cgImage else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func pngData(from image: NSImage) -> Data? {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return rep.representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
