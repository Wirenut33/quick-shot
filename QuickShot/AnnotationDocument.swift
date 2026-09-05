//
//  AnnotationDocument.swift
//  QuickShot
//

import AppKit
import Combine

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select = "Select", rectangle = "Rectangle", arrow = "Arrow", highlight = "Highlight", text = "Text"
    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable {
    case red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", blue = "Blue", black = "Black"
    var id: String { rawValue }
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .black: return .black
        }
    }
}

struct AnnotationStyle: Equatable {
    var color: AnnotationColor = .red
    var width: CGFloat = 6
    var fontSize: CGFloat = 32
    var bold = true
    var dashed = false
}

struct AnnotationMark: Equatable, Identifiable {
    enum Kind: Equatable { case rectangle, arrow, highlight, text(String) }
    let id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var style = AnnotationStyle()
    // The point on the curve at t = 0.5, so dragging the middle handle
    // follows the pointer exactly, instead of moving an invisible control point.
    var bend: CGPoint? = nil
    var midpoint: CGPoint { bend ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }
    var control: CGPoint {
        CGPoint(x: 2 * midpoint.x - (start.x + end.x) / 2,
                y: 2 * midpoint.y - (start.y + end.y) / 2)
    }
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
                       y: u*u*start.y + 2*u*t*control.y + t*t*end.y)
    }
    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: style.fontSize, weight: style.bold ? .bold : .regular),
         .foregroundColor: style.color.nsColor,
         .strokeColor: NSColor.white, .strokeWidth: -2.5]
    }
    var bounds: CGRect {
        if case .text(let text) = kind { return CGRect(origin: start, size: (text as NSString).size(withAttributes: textAttributes)) }
        return CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
    }
    func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow:
            return (0..<48).contains { index in
                let a = point(at: CGFloat(index)/48), b = point(at: CGFloat(index+1)/48)
                let dx = b.x-a.x, dy = b.y-a.y
                let t = max(0, min(1, ((p.x-a.x)*dx + (p.y-a.y)*dy) / max(dx*dx+dy*dy, 0.001)))
                return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy) <= tolerance + style.width/2
            }
        case .rectangle:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
                && !bounds.insetBy(dx: tolerance + style.width/2, dy: tolerance + style.width/2).contains(p)
        case .highlight, .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }
}

final class AnnotationDocument: ObservableObject {
    let image: NSImage

    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var annotations: [AnnotationMark] = []
    @Published var textDraft = ""
    @Published var descriptionText = ""
    @Published var canvasPadding: CGFloat = 36
    @Published var statusMessage = "Draw a mark, then select it to move, resize, or style it."
    @Published var selectedID: UUID?
    @Published var style = AnnotationStyle()
    @Published private(set) var undoStack: [[AnnotationMark]] = []
    @Published private(set) var redoStack: [[AnnotationMark]] = []
    private var editStart: [AnnotationMark]?
    var selectedMark: AnnotationMark? { annotations.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func select(_ id: UUID?) {
        selectedID = id
        if let mark = selectedMark {
            style = mark.style
            if case .text(let text) = mark.kind { textDraft = text }
            statusMessage = mark.kind == .arrow ? "Drag either end or the middle handle to bend the arrow." : "Drag the mark to move it; drag a corner to resize."
        } else {
            statusMessage = selectedTool == .text ? "Type a label, then click the canvas to place it." : "Draw a mark, then select it to move, resize, or style it."
        }
    }
    func checkpoint() {
        undoStack.append(annotations)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func beginEdit() { editStart = annotations }
    func endEdit() {
        if let before = editStart, before != annotations {
            undoStack.append(before)
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        editStart = nil
    }
    func replace(_ mark: AnnotationMark) {
        if let i = annotations.firstIndex(where: { $0.id == mark.id }) { annotations[i] = mark }
    }
    func applyStyle(_ value: AnnotationStyle) {
        style = value
        guard var mark = selectedMark, mark.style != value else { return }
        checkpoint(); mark.style = value; replace(mark)
    }
    func updateText() {
        guard var mark = selectedMark, case .text = mark.kind,
              !textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              mark.kind != .text(textDraft) else { return }
        checkpoint(); mark.kind = .text(textDraft); replace(mark)
    }
    func deleteSelected() {
        guard selectedMark != nil else { return }
        checkpoint(); annotations.removeAll { $0.id == selectedID }; selectedID = nil
    }
    func makeMark(from start: CGPoint, to end: CGPoint) -> AnnotationMark {
        let kind: AnnotationMark.Kind
        switch selectedTool {
        case .arrow: kind = .arrow
        case .highlight: kind = .highlight
        case .text: kind = .text(textDraft)
        default: kind = .rectangle
        }
        return AnnotationMark(kind: kind, start: start, end: end, style: style)
    }

    init(image: NSImage) {
        self.image = image
    }

    var descriptionHeight: CGFloat {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 116
    }

    var canvasSize: NSSize {
        NSSize(
            width: image.size.width + (canvasPadding * 2),
            height: image.size.height + (canvasPadding * 2) + descriptionHeight
        )
    }

    var imageOrigin: CGPoint {
        CGPoint(x: canvasPadding, y: canvasPadding)
    }

    var displayScale: CGFloat {
        min(1, 1_080 / canvasSize.width, 620 / canvasSize.height)
    }

    func add(_ mark: AnnotationMark) {
        checkpoint()
        annotations.append(mark)
        selectedTool = .select
        select(mark.id)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations); annotations = previous; select(nil)
        statusMessage = "Undone."
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations); annotations = next; select(nil)
        statusMessage = "Redone."
    }

    func clear() {
        guard !annotations.isEmpty else { return }
        checkpoint(); annotations.removeAll(); select(nil)
        statusMessage = "Annotations cleared. Undo to restore them."
    }

    func expandCanvas() {
        canvasPadding = min(canvasPadding + 72, 360)
        statusMessage = "Canvas expanded."
    }

    func draw(in context: NSGraphicsContext, preview: AnnotationMark? = nil) {
        let size = canvasSize
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        image.draw(
            in: NSRect(origin: imageOrigin, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )

        for annotation in annotations {
            draw(annotation)
        }
        if let preview {
            draw(preview)
        }

        drawDescriptionIfNeeded()
    }

    func renderedImage() -> NSImage? {
        let size = canvasSize
        guard size.width > 0, size.height > 0,
              let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width.rounded(.up)),
                pixelsHigh: Int(size.height.rounded(.up)),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        draw(in: graphicsContext)
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: size)
        result.addRepresentation(representation)
        return result
    }

    func pngData() -> Data? {
        guard let image = renderedImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    @discardableResult
    func copyToClipboard() -> Bool {
        guard let renderedImage = renderedImage(), let pngData = pngData() else {
            statusMessage = "QuickShot could not render the annotated screenshot."
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wroteImage = pasteboard.writeObjects([renderedImage])
        pasteboard.setData(pngData, forType: .png)
        statusMessage = wroteImage ? "Annotated screenshot copied. Paste it anywhere." : "Copy failed."
        return wroteImage
    }

    @discardableResult
    func save(to url: URL, copyPath: Bool) -> Bool {
        guard let data = pngData() else {
            statusMessage = "QuickShot could not render the annotated screenshot."
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            if copyPath {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
                statusMessage = "Saved and copied the file path."
            } else {
                statusMessage = "Saved \(url.lastPathComponent)."
            }
            return true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func translated(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + imageOrigin.x, y: point.y + imageOrigin.y)
    }

    private func draw(_ annotation: AnnotationMark) {
        let start = translated(annotation.start)
        let end = translated(annotation.end)
        let color = annotation.style.color.nsColor

        switch annotation.kind {
        case .rectangle, .highlight:
            let rect = NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            color.setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = annotation.style.width
            if annotation.kind == .highlight {
                color.withAlphaComponent(0.3).setFill()
                path.fill()
            } else {
                if annotation.style.dashed { path.setLineDash([12, 8], count: 2, phase: 0) }
                path.stroke()
            }

        case .arrow:
            drawArrow(annotation, from: start, to: end, color: color)

        case .text(let text):
            (text as NSString).draw(at: start, withAttributes: annotation.textAttributes)
        }
    }

    private func drawArrow(_ mark: AnnotationMark, from start: CGPoint, to end: CGPoint, color: NSColor) {
        let line = NSBezierPath()
        line.move(to: start)
        let control = translated(mark.control)
        line.curve(to: end,
                   controlPoint1: CGPoint(x: start.x + 2/3 * (control.x-start.x), y: start.y + 2/3 * (control.y-start.y)),
                   controlPoint2: CGPoint(x: end.x + 2/3 * (control.x-end.x), y: end.y + 2/3 * (control.y-end.y)))
        line.lineWidth = mark.style.width
        if mark.style.dashed { line.setLineDash([12, 8], count: 2, phase: 0) }
        line.lineCapStyle = .round
        color.setStroke()
        line.stroke()

        let tangent = hypot(end.x - control.x, end.y - control.y) > 0.001 ? control : start
        let angle = atan2(end.y - tangent.y, end.x - tangent.x)
        let headLength: CGFloat = max(16, mark.style.width * 4)
        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        let head = NSBezierPath()
        head.move(to: left)
        head.line(to: end)
        head.line(to: right)
        head.lineWidth = mark.style.width
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()
    }

    private func drawDescriptionIfNeeded() {
        let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }

        let separatorY = image.size.height + (canvasPadding * 2)
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: CGPoint(x: canvasPadding, y: separatorY))
        separator.line(to: CGPoint(x: canvasSize.width - canvasPadding, y: separatorY))
        separator.lineWidth = 2
        separator.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let rect = NSRect(
            x: canvasPadding,
            y: separatorY + 18,
            width: canvasSize.width - (canvasPadding * 2),
            height: descriptionHeight - 28
        )
        (description as NSString).draw(in: rect, withAttributes: attributes)
    }
}
