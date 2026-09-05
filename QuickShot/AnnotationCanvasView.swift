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
    private var originalMark: AnnotationMark?
    private var activeHandle: Int?
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
        addCursorRect(bounds, cursor: document.selectedTool == .select ? .arrow : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        context.cgContext.scaleBy(x: displayScale, y: displayScale)
        document.draw(in: context, preview: previewMark)
        if let mark = document.selectedMark, document.selectedTool == .select {
            NSColor.controlAccentColor.setStroke()
            let origin = document.imageOrigin
            if mark.kind != .arrow {
                let box = NSBezierPath(rect: mark.bounds.offsetBy(dx: origin.x, dy: origin.y))
                box.lineWidth = 1 / displayScale
                box.setLineDash([4 / displayScale, 4 / displayScale], count: 2, phase: 0)
                box.stroke()
            }
            for point in handles(for: mark) {
                let radius = 5 / displayScale
                let path = NSBezierPath(ovalIn: CGRect(x: point.x + origin.x - radius, y: point.y + origin.y - radius, width: 2 * radius, height: 2 * radius))
                NSColor.white.setFill(); path.fill()
                NSColor.controlAccentColor.setStroke(); path.lineWidth = 1.5 / displayScale; path.stroke()
            }
        }
        context.restoreGraphicsState()
    }

    private func handles(for mark: AnnotationMark) -> [CGPoint] {
        if mark.kind == .arrow { return [mark.start, mark.midpoint, mark.end] }
        let r = mark.bounds
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { document.deleteSelected() }
        else if event.keyCode == 53 { document.select(nil) }
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = modelPoint(for: event)
        if document.selectedTool == .select {
            if let selected = document.selectedMark {
                activeHandle = handles(for: selected).firstIndex { hypot($0.x-point.x, $0.y-point.y) < 10 / displayScale }
            }
            if activeHandle == nil {
                document.select(document.annotations.reversed().first { $0.contains(point, tolerance: 7 / displayScale) }?.id)
            }
            originalMark = document.selectedMark
            if originalMark != nil { document.beginEdit(); startPoint = point }
            needsDisplay = true
            return
        }
        document.select(nil)
        if document.selectedTool == .text {
            guard !document.textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                document.statusMessage = "Type a label first, then click where it belongs."
                return
            }
            document.add(document.makeMark(from: point, to: point))
            return
        }
        startPoint = point; currentPoint = point; needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let point = modelPoint(for: event)
        if var mark = originalMark {
            if let handle = activeHandle {
                if mark.kind == .arrow {
                    switch handle {
                    case 0: mark.start = point
                    case 1: mark.bend = point
                    default: mark.end = point
                    }
                } else {
                    let corners = handles(for: mark)
                    let anchor = corners[(handle + 2) % 4]
                    if case .text = mark.kind {
                        let oldDistance = hypot(corners[handle].x-anchor.x, corners[handle].y-anchor.y)
                        let ratio = hypot(point.x-anchor.x, point.y-anchor.y) / max(1, oldDistance)
                        mark.style.fontSize = min(144, max(12, mark.style.fontSize * ratio))
                        let size = mark.bounds.size
                        mark.start = CGPoint(x: (handle == 0 || handle == 3) ? anchor.x-size.width : anchor.x,
                                             y: handle < 2 ? anchor.y-size.height : anchor.y)
                    } else { mark.start = anchor; mark.end = point }
                }
            } else {
                let dx = point.x-startPoint.x, dy = point.y-startPoint.y
                mark.start.x += dx; mark.start.y += dy
                mark.end.x += dx; mark.end.y += dy
                if let bend = mark.bend { mark.bend = CGPoint(x: bend.x+dx, y: bend.y+dy) }
            }
            document.replace(mark)
        } else { currentPoint = point }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        if originalMark != nil {
            mouseDragged(with: event)
            document.endEdit()
            document.select(document.selectedID)
        } else {
            let end = modelPoint(for: event)
            if hypot(end.x-startPoint.x, end.y-startPoint.y) > 4 {
                document.add(document.makeMark(from: startPoint, to: end))
            }
        }
        self.startPoint = nil; currentPoint = nil; originalMark = nil; activeHandle = nil
        needsDisplay = true
    }

    private var previewMark: AnnotationMark? {
        guard originalMark == nil, let startPoint, let currentPoint else { return nil }
        return document.makeMark(from: startPoint, to: currentPoint)
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
            DispatchQueue.main.async { self?.needsDisplay = true; if let self { self.window?.invalidateCursorRects(for: self) } }
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
