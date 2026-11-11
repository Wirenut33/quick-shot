//
//  AnnotationCanvasView.swift
//  QuickShot
//

import AppKit
import Combine
import SwiftUI

final class AnnotationCanvasNSView: NSView, NSTextFieldDelegate {
    var document: AnnotationDocument {
        didSet {
            guard oldValue !== document else { return }
            cancelTextEdit()
            observeDocument()
        }
    }
    var displayScale: CGFloat {
        didSet { if oldValue != displayScale { layoutTextField() } }
    }

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var originalMark: AnnotationMark?
    private var activeHandle: Int?
    private var placingVertex = false
    private var observation: AnyCancellable?
    // Typing a label happens in a text field placed on the canvas.
    private var textField: NSTextField?
    private var textOrigin = CGPoint.zero
    private var editingMarkID: UUID?
    private var finishingTextEdit = false

    init(document: AnnotationDocument, displayScale: CGFloat) {
        self.document = document
        self.displayScale = displayScale
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot canvas")
        setAccessibilityHelp("Draw with the selected tool. Press a tool's letter to switch tools.")
        observeDocument()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        document.backingScale = window.backingScaleFactor
        // Single-key tools only work while the canvas has focus, so take it up front
        // instead of leaving it with the description field.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window, self.textField == nil else { return }
            window.makeFirstResponder(self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window { document.backingScale = window.backingScaleFactor }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // Shows the next polyline segment following the pointer.
    override func mouseMoved(with event: NSEvent) {
        guard document.selectedTool == .polyline, !document.polylineDraft.isEmpty else { return }
        currentPoint = modelPoint(for: event)
        needsDisplay = true
    }

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
            if !mark.isPath {
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
        switch mark.kind {
        case .arrow, .line: return [mark.start, mark.midpoint, mark.end]
        case .polyline: return mark.points
        default: break
        }
        let r = mark.bounds
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    override func keyDown(with event: NSEvent) {
        let drafting = !document.polylineDraft.isEmpty
        // A key that edits the draft ends any press in progress, so its release adds nothing.
        if drafting { placingVertex = false }
        if event.keyCode == 51 || event.keyCode == 117 {
            if drafting { document.removeLastPolylinePoint() } else { document.deleteSelected() }
        } else if event.keyCode == 53 {
            // Escape backs out one step at a time: the draft, then the selection, and
            // only then asks the window to close.
            if drafting { document.cancelPolyline() }
            else if document.selectedID != nil { document.select(nil) }
            else { document.onKeyCommand?(.escape) }
        } else if drafting, event.keyCode == 36 || event.keyCode == 76 {
            document.finishPolyline()
        } else if let tool = tool(for: event) {
            document.selectedTool = tool
        } else { super.keyDown(with: event) }
        needsDisplay = true
    }

    /// A bare letter picks a tool. Keys with Command, Control or Option are left alone.
    private func tool(for event: NSEvent) -> AnnotationTool? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return nil }
        return AnnotationTool.allCases.first { $0.shortcutKey == key }
    }

    /// Editor-wide shortcuts. They reach this view whichever control has focus, so the
    /// ones that would fight with text editing are limited to when the canvas has it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, event.window === window, modifiers.contains(.command),
              !modifiers.contains(.control), !modifiers.contains(.option),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = modifiers.contains(.shift)
        switch key {
        case "s":
            document.onKeyCommand?(shift ? .saveAs : .save)
        case "c" where !shift && window?.firstResponder === self:
            document.onKeyCommand?(.copy)
        case "=", "+":
            document.zoomIn()
        case "-" where !shift:
            document.zoomOut()
        case "0" where !shift:
            document.zoomToActualSize()
        case "1" where !shift:
            document.zoomToFit()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if textField != nil {
            // A click outside the label being typed finishes it and does nothing else.
            commitTextEdit()
            return
        }
        window?.makeFirstResponder(self)
        let point = modelPoint(for: event)
        if document.selectedTool == .select {
            if event.clickCount > 1,
               let mark = document.annotations.reversed().first(where: { $0.contains(point, tolerance: 7 / displayScale) }),
               case .text = mark.kind {
                document.select(mark.id)
                beginTextEdit(at: mark.start, editing: mark)
                return
            }
            if let selected = document.selectedMark {
                // The nearest handle wins, so a middle dot slid close to an end stays grabbable.
                let distances = handles(for: selected).map { hypot($0.x-point.x, $0.y-point.y) }
                activeHandle = distances.indices.filter { distances[$0] < 10 / displayScale }.min { distances[$0] < distances[$1] }
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
        if document.selectedTool == .polyline {
            if event.clickCount > 1 { document.finishPolyline() }
            else { document.addPolylinePoint(point); placingVertex = true }
            currentPoint = point; needsDisplay = true
            return
        }
        if document.selectedTool == .text {
            beginTextEdit(at: point, editing: nil)
            return
        }
        startPoint = point; currentPoint = point; needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if placingVertex { currentPoint = modelPoint(for: event); needsDisplay = true; return }
        guard let startPoint else { return }
        let point = modelPoint(for: event)
        if var mark = originalMark {
            if let handle = activeHandle {
                switch mark.kind {
                case .arrow:
                    switch handle {
                    case 0: mark.start = point
                    case 1: mark.bend = point
                    default: mark.end = point
                    }
                case .line:
                    if handle == 1 { mark.bend = mark.lineBend(for: point, tolerance: 8 / displayScale) }
                    else { mark.moveLineEnd(handle, to: point) }
                case .polyline:
                    mark.points[handle] = point
                default:
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
                mark.offset(dx: point.x-startPoint.x, dy: point.y-startPoint.y)
            }
            document.replace(mark)
        } else { currentPoint = point }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if placingVertex {
            // Dragging while placing a point lays down a segment, like the Line tool.
            placingVertex = false
            document.addPolylinePoint(modelPoint(for: event))
            needsDisplay = true
            return
        }
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
        if document.selectedTool == .polyline, !document.polylineDraft.isEmpty {
            return .polyline(document.polylineDraft + (currentPoint.map { [$0] } ?? []), style: document.style)
        }
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
        document.commitPendingEdits = { [weak self] in self?.commitTextEdit() }
        observation = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.needsDisplay = true
                self.styleTextField()
                self.window?.invalidateCursorRects(for: self)
            }
        }
        needsDisplay = true
    }

    // MARK: Typing a label in place

    var isEditingText: Bool { textField != nil }

    /// Opens a text field at `point` (image coordinates). Pass a label to edit it.
    func beginTextEdit(at point: CGPoint, editing mark: AnnotationMark?) {
        commitTextEdit()
        let field = NSTextField(string: "")
        if let mark, case .text(let text) = mark.kind {
            field.stringValue = text
            editingMarkID = mark.id
            document.hiddenMarkID = mark.id
        }
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel("Label text")
        field.wantsLayer = true
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.layer?.borderWidth = 1
        textOrigin = point
        textField = field
        addSubview(field)
        styleTextField()
        window?.makeFirstResponder(field)
        document.statusMessage = "Type the label. Return finishes, Escape cancels."
    }

    /// Replaces the text being typed. Used by tests in place of key presses.
    func setEditingText(_ text: String) {
        textField?.stringValue = text
        layoutTextField()
    }

    func commitTextEdit() {
        guard let field = textField, !finishingTextEdit else { return }
        let text = field.stringValue
        let id = editingMarkID
        endTextEdit()
        if let id {
            document.setText(text, for: id)
            if document.annotations.contains(where: { $0.id == id }) { document.select(id) }
        } else if !document.addText(text, at: textOrigin) {
            document.statusMessage = document.hint(for: document.selectedTool)
        }
        needsDisplay = true
    }

    func cancelTextEdit() {
        guard textField != nil, !finishingTextEdit else { return }
        endTextEdit()
        document.statusMessage = document.hint(for: document.selectedTool)
        needsDisplay = true
    }

    private func endTextEdit() {
        // Removing the field ends its editing session, which would otherwise call back in.
        finishingTextEdit = true
        defer { finishingTextEdit = false }
        let field = textField
        textField = nil
        editingMarkID = nil
        if document.hiddenMarkID != nil { document.hiddenMarkID = nil }
        field?.delegate = nil
        if let field, window?.firstResponder === field.currentEditor() || window?.firstResponder === field {
            window?.makeFirstResponder(self)
        }
        field?.removeFromSuperview()
    }

    private func styleTextField() {
        guard let field = textField else { return }
        let style = editingMarkID.flatMap { id in document.annotations.first { $0.id == id }?.style }
            ?? document.style(for: .text)
        field.font = NSFont.systemFont(ofSize: max(6, style.fontSize * displayScale), weight: style.bold ? .bold : .regular)
        field.textColor = style.color.nsColor
        layoutTextField()
    }

    private func layoutTextField() {
        guard let field = textField else { return }
        let fitting = field.cell?.cellSize ?? field.fittingSize
        let origin = CGPoint(x: (textOrigin.x + document.imageOrigin.x) * displayScale - 2,
                             y: (textOrigin.y + document.imageOrigin.y) * displayScale - 1)
        let width = min(max(fitting.width + 16, 140), max(140, bounds.maxX - origin.x))
        field.frame = CGRect(x: origin.x, y: origin.y, width: width, height: fitting.height)
    }

    func controlTextDidChange(_ notification: Notification) {
        layoutTextField()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEdit()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            commitTextEdit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEdit()
            return true
        }
        return false
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
