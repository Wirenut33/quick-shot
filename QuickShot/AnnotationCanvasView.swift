//
//  AnnotationCanvasView.swift
//  QuickShot
//

import AppKit
import Combine
import SwiftUI

final class AnnotationCanvasNSView: NSView {
    var document: AnnotationDocument {
        didSet { observeDocument() }
    }
    var displayScale: CGFloat

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var observation: AnyCancellable?

    init(document: AnnotationDocument, displayScale: CGFloat) {
        self.document = document
        self.displayScale = displayScale
        super.init(frame: .zero)
        observeDocument()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        context.cgContext.scaleBy(x: displayScale, y: displayScale)
        document.draw(in: context, preview: previewMark)
        context.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = modelPoint(for: event)

        if document.selectedTool == .text {
            let text = document.textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                document.statusMessage = "Type a label first, then click where it belongs."
                return
            }
            document.add(AnnotationMark(kind: .text(text), start: point, end: point))
            return
        }

        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = modelPoint(for: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let endPoint = modelPoint(for: event)
        let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)

        if distance > 4 {
            let kind: AnnotationMark.Kind = document.selectedTool == .arrow ? .arrow : .rectangle
            document.add(AnnotationMark(kind: kind, start: startPoint, end: endPoint))
        }

        self.startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    private var previewMark: AnnotationMark? {
        guard let startPoint, let currentPoint else { return nil }
        let kind: AnnotationMark.Kind = document.selectedTool == .arrow ? .arrow : .rectangle
        return AnnotationMark(kind: kind, start: startPoint, end: currentPoint)
    }

    private func modelPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        let fullResolution = CGPoint(x: local.x / displayScale, y: local.y / displayScale)
        let relative = CGPoint(
            x: fullResolution.x - document.imageOrigin.x,
            y: fullResolution.y - document.imageOrigin.y
        )
        return CGPoint(
            x: min(max(relative.x, -document.canvasPadding), document.image.size.width + document.canvasPadding),
            y: min(max(relative.y, -document.canvasPadding), document.image.size.height + document.canvasPadding)
        )
    }

    private func observeDocument() {
        observation = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
        needsDisplay = true
    }
}

struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    let displayScale: CGFloat

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        AnnotationCanvasNSView(document: document, displayScale: displayScale)
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.document = document
        nsView.displayScale = displayScale
        nsView.needsDisplay = true
    }
}
