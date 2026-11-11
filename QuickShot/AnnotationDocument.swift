//
//  AnnotationDocument.swift
//  QuickShot
//

import AppKit
import Combine

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select = "Select", rectangle = "Rectangle", arrow = "Arrow", line = "Line", polyline = "Polyline"
    case highlight = "Highlight", text = "Text", redact = "Redact"
    var id: String { rawValue }
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .polyline: return "point.3.connected.trianglepath.dotted"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .redact: return "eye.slash"
        }
    }
    /// Pressed on its own while the canvas has focus.
    var shortcutKey: String {
        switch self {
        case .select: return "V"
        case .rectangle: return "R"
        case .arrow: return "A"
        case .line: return "L"
        case .polyline: return "P"
        case .highlight: return "H"
        case .text: return "T"
        case .redact: return "B"
        }
    }
    /// What a new mark looks like before the user has chosen otherwise.
    var defaultStyle: AnnotationStyle {
        switch self {
        case .highlight: return AnnotationStyle(color: .yellow)
        case .redact: return AnnotationStyle(color: .black)
        default: return AnnotationStyle()
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable, Codable {
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

struct AnnotationStyle: Equatable, Codable {
    var color: AnnotationColor = .red
    var width: CGFloat = 6
    var fontSize: CGFloat = 32
    var bold = true
    var dashed = false
    /// Redact only. Off covers the area with an opaque fill, which is the only style that
    /// cannot be read back. On keeps a coarse mosaic of what was there.
    var pixelate = false
}

struct AnnotationMark: Equatable, Identifiable {
    enum Kind: Equatable { case rectangle, arrow, line, polyline, highlight, redact, text(String) }
    /// The tool that draws this kind of mark.
    var tool: AnnotationTool {
        switch kind {
        case .rectangle: return .rectangle
        case .arrow: return .arrow
        case .line: return .line
        case .polyline: return .polyline
        case .highlight: return .highlight
        case .redact: return .redact
        case .text: return .text
        }
    }
    let id = UUID()
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var style = AnnotationStyle()
    // Vertices of a polyline; start and end mirror its first and last points.
    var points: [CGPoint] = [] {
        didSet { if let first = points.first, let last = points.last { start = first; end = last } }
    }
    // A point the curve passes through, so dragging the middle handle follows the pointer
    // exactly instead of moving an invisible control point. Arrows pass through it at t = 0.5;
    // lines anywhere along their length (see lineCurves).
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
    // A bent line runs through start, bend, and end as two cubic segments. Its direction at the bend
    // is parallel to start→end, so a bend that lies on the line slides along it and keeps it straight.
    // Each side's tangent is capped at the bend's distance from that end along the line, so the curve
    // never swings past an end before returning to it.
    var lineCurves: [[CGPoint]] {
        guard kind == .line, let b = bend else { return [] }
        let dx = end.x-start.x, dy = end.y-start.y, length = max(hypot(dx, dy), 0.001)
        let ux = dx/length, uy = dy/length
        let along = (b.x-start.x)*ux + (b.y-start.y)*uy
        let inLength = min(hypot(b.x-start.x, b.y-start.y)/3, max(0, along))
        let outLength = min(hypot(end.x-b.x, end.y-b.y)/3, max(0, length - along))
        let into = CGPoint(x: b.x-ux*inLength, y: b.y-uy*inLength)
        let out = CGPoint(x: b.x+ux*outLength, y: b.y+uy*outLength)
        return [[start, CGPoint(x: (start.x+into.x)/2, y: (start.y+into.y)/2), into, b],
                [b, out, CGPoint(x: (end.x+out.x)/2, y: (end.y+out.y)/2), end]]
    }
    // Where a dragged line handle lands: within `tolerance` of the straight line it snaps onto it,
    // short of either end, so the handle slides along the line without curving it.
    func lineBend(for p: CGPoint, tolerance: CGFloat) -> CGPoint {
        let dx = end.x-start.x, dy = end.y-start.y, lengthSquared = dx*dx + dy*dy
        guard lengthSquared > 1 else { return p }
        let t = ((p.x-start.x)*dx + (p.y-start.y)*dy) / lengthSquared
        let distance = abs((p.x-start.x)*dy - (p.y-start.y)*dx) / sqrt(lengthSquared)
        guard distance <= tolerance else { return p }
        let along = max(0.05, min(0.95, t))
        return CGPoint(x: start.x + along*dx, y: start.y + along*dy)
    }
    // Moves one end of a line and carries its bend along, keeping the bend's place along and across
    // the line, so a curve keeps its shape and a straight line stays straight.
    mutating func moveLineEnd(_ index: Int, to p: CGPoint) {
        let oldStart = start, oldEnd = end
        if index == 0 { start = p } else { end = p }
        guard let b = bend else { return }
        let dx = oldEnd.x-oldStart.x, dy = oldEnd.y-oldStart.y, lengthSquared = dx*dx + dy*dy
        guard lengthSquared > 0.001 else { return }
        let ax = b.x-oldStart.x, ay = b.y-oldStart.y
        let along = (ax*dx + ay*dy) / lengthSquared, across = (ax*dy - ay*dx) / lengthSquared
        let nx = end.x-start.x, ny = end.y-start.y
        bend = CGPoint(x: start.x + along*nx + across*ny, y: start.y + along*ny - across*nx)
    }
    static func polyline(_ points: [CGPoint], style: AnnotationStyle) -> AnnotationMark {
        AnnotationMark(kind: .polyline, start: points.first ?? .zero, end: points.last ?? .zero, style: style, points: points)
    }
    // Arrows, lines, and polylines are drawn and hit-tested along these points rather than a box.
    var isPath: Bool { kind == .arrow || kind == .line || kind == .polyline }
    var pathPoints: [CGPoint] {
        switch kind {
        case .arrow: return (0...48).map { point(at: CGFloat($0)/48) }
        case .polyline: return points
        case .line where bend != nil:
            return [start] + lineCurves.flatMap { c in
                (1...24).map { step -> CGPoint in
                    let t = CGFloat(step)/24, u = 1-t
                    return CGPoint(x: u*u*u*c[0].x + 3*u*u*t*c[1].x + 3*u*t*t*c[2].x + t*t*t*c[3].x,
                                   y: u*u*u*c[0].y + 3*u*u*t*c[1].y + 3*u*t*t*c[2].y + t*t*t*c[3].y)
                }
            }
        default: return [start, end]
        }
    }
    var bounds: CGRect {
        if case .text(let text) = kind { return CGRect(origin: start, size: (text as NSString).size(withAttributes: textAttributes)) }
        if kind == .polyline, let first = points.first {
            return points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
        return CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(end.x-start.x), height: abs(end.y-start.y))
    }
    mutating func offset(dx: CGFloat, dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
        if let bend { self.bend = CGPoint(x: bend.x+dx, y: bend.y+dy) }
        if !points.isEmpty { points = points.map { CGPoint(x: $0.x+dx, y: $0.y+dy) } }
    }
    func contains(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case .arrow, .line, .polyline:
            let path = pathPoints
            return zip(path, path.dropFirst()).contains { a, b in
                let dx = b.x-a.x, dy = b.y-a.y
                let t = max(0, min(1, ((p.x-a.x)*dx + (p.y-a.y)*dy) / max(dx*dx+dy*dy, 0.001)))
                return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy) <= tolerance + style.width/2
            }
        case .rectangle:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
                && !bounds.insetBy(dx: tolerance + style.width/2, dy: tolerance + style.width/2).contains(p)
        case .highlight, .redact, .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }
}

enum EditorZoom: Equatable {
    /// Shrink to fit the window, never enlarging beyond one point per pixel.
    case fit
    /// A fixed number of points per image pixel.
    case scale(CGFloat)
}

/// Commands the canvas receives from the keyboard and hands to the window.
enum EditorKeyCommand { case save, saveAs, copy, escape }

final class AnnotationDocument: ObservableObject {
    let image: NSImage

    @Published var selectedTool: AnnotationTool = .rectangle {
        didSet {
            guard oldValue != selectedTool else { return }
            // Leaving the polyline tool keeps whatever line was in progress.
            if oldValue == .polyline { commitPolyline(selecting: false) }
            // Each drawing tool remembers its own look, so Highlight's yellow never
            // becomes the colour of the next arrow.
            if selectedTool != .select {
                selectedID = nil
                style = style(for: selectedTool)
                statusMessage = hint(for: selectedTool)
            }
        }
    }
    @Published private(set) var polylineDraft: [CGPoint] = []
    @Published var annotations: [AnnotationMark] = []
    @Published var descriptionText = ""
    @Published var zoom: EditorZoom = .fit
    /// A text label being edited in place is drawn by its text field instead.
    @Published var hiddenMarkID: UUID?
    /// Remembered look per tool. Set `onToolStyleChange` to store changes.
    var toolStyles: [AnnotationTool: AnnotationStyle] = [:]
    var onToolStyleChange: ((AnnotationTool, AnnotationStyle) -> Void)?
    /// Finishes anything still being typed on the canvas before an export.
    var commitPendingEdits: (() -> Void)?
    var onKeyCommand: ((EditorKeyCommand) -> Void)?
    /// Device pixels per point of the screen showing the editor; 100% zoom means one
    /// image pixel per device pixel.
    var backingScale: CGFloat = 2
    private(set) var lastDisplayScale: CGFloat = 1
    private var cleanState: SavedState?
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
            switch mark.kind {
            case .arrow: statusMessage = "Drag either end or the middle handle to bend the arrow."
            case .line: statusMessage = "Drag either end to adjust the line; slide or pull the middle dot to curve it."
            case .polyline: statusMessage = "Drag any point to reshape the line."
            case .text: statusMessage = "Drag to move; drag a corner to resize; double-click to edit the text."
            default: statusMessage = "Drag the mark to move it; drag a corner to resize."
            }
        } else {
            statusMessage = hint(for: selectedTool)
        }
    }

    func hint(for tool: AnnotationTool) -> String {
        switch tool {
        case .text: return "Click where the label belongs, then type. Return finishes."
        case .polyline: return polylineHint
        case .redact: return "Drag over anything that must not be readable."
        case .select: return "Click a mark to select it."
        default: return "Draw a mark, then select it to move, resize, or style it."
        }
    }

    func style(for tool: AnnotationTool) -> AnnotationStyle {
        toolStyles[tool] ?? tool.defaultStyle
    }

    private func remember(_ value: AnnotationStyle, for tool: AnnotationTool) {
        guard tool != .select, toolStyles[tool] != value else { return }
        toolStyles[tool] = value
        onToolStyleChange?(tool, value)
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
        guard var mark = selectedMark else {
            remember(value, for: selectedTool)
            return
        }
        remember(value, for: mark.tool)
        guard mark.style != value else { return }
        checkpoint(); mark.style = value; replace(mark)
    }
    /// Places a new label. Blank text places nothing.
    @discardableResult
    func addText(_ text: String, at point: CGPoint) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        add(AnnotationMark(kind: .text(text), start: point, end: point, style: style(for: .text)))
        return true
    }
    /// Changes a label's text in one undo step. Blank text removes the label.
    func setText(_ text: String, for id: UUID) {
        guard var mark = annotations.first(where: { $0.id == id }), case .text = mark.kind,
              mark.kind != .text(text) else { return }
        checkpoint()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.removeAll { $0.id == id }
            if selectedID == id { select(nil) }
        } else {
            mark.kind = .text(text)
            replace(mark)
        }
    }
    func deleteSelected() {
        guard selectedMark != nil else { return }
        checkpoint(); annotations.removeAll { $0.id == selectedID }; selectedID = nil
    }
    func makeMark(from start: CGPoint, to end: CGPoint) -> AnnotationMark {
        let kind: AnnotationMark.Kind
        switch selectedTool {
        case .arrow: kind = .arrow
        case .line: kind = .line
        case .highlight: kind = .highlight
        case .redact: kind = .redact
        default: kind = .rectangle
        }
        return AnnotationMark(kind: kind, start: start, end: end, style: style)
    }

    let polylineHint = "Click to add points; double-click or press Return to finish, Escape to cancel."
    func addPolylinePoint(_ point: CGPoint) {
        if let last = polylineDraft.last, hypot(point.x-last.x, point.y-last.y) <= 4 { return }
        polylineDraft.append(point)
        statusMessage = polylineDraft.count == 1 ? polylineHint : "\(polylineDraft.count) points. Double-click or press Return to finish."
    }
    func removeLastPolylinePoint() {
        guard !polylineDraft.isEmpty else { return }
        polylineDraft.removeLast()
        statusMessage = polylineHint
    }
    @discardableResult
    func finishPolyline() -> Bool { commitPolyline(selecting: true) }
    func cancelPolyline() {
        guard !polylineDraft.isEmpty else { return }
        polylineDraft = []
        statusMessage = "Line canceled."
    }
    @discardableResult
    private func commitPolyline(selecting: Bool) -> Bool {
        let points = polylineDraft
        guard !points.isEmpty else { return false }
        polylineDraft = []
        guard points.count >= 2 else {
            statusMessage = "A line needs at least two points."
            return false
        }
        let mark = AnnotationMark.polyline(points, style: style)
        if selecting { add(mark) } else { checkpoint(); annotations.append(mark) }
        return true
    }

    init(image: NSImage) {
        self.image = image
        cleanState = currentState
    }

    // MARK: Unsaved work

    private struct SavedState: Equatable {
        var annotations: [AnnotationMark]
        var descriptionText: String
        var canvasPadding: CGFloat
    }

    private var currentState: SavedState {
        SavedState(annotations: annotations, descriptionText: descriptionText, canvasPadding: canvasPadding)
    }

    /// True when something changed since the editor opened or the image was last
    /// copied, saved or added to the collection.
    var hasUnsavedChanges: Bool { cleanState != currentState || !polylineDraft.isEmpty }

    func markClean() { cleanState = currentState }

    // MARK: Zoom

    static let zoomSteps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    /// Points per image pixel for the space the canvas has.
    func displayScale(fitting available: CGSize) -> CGFloat {
        let scale: CGFloat
        switch zoom {
        case .fit:
            guard available.width > 0, available.height > 0 else { return displayScale }
            scale = max(0.02, min(1, available.width / canvasSize.width, available.height / canvasSize.height))
        case .scale(let value):
            scale = value
        }
        lastDisplayScale = scale
        return scale
    }

    /// Zoom as a share of true size, where 100 is one image pixel per device pixel.
    var zoomPercent: Int { Int((lastDisplayScale * backingScale * 100).rounded()) }

    func zoomIn() { step(by: 1) }
    func zoomOut() { step(by: -1) }
    func zoomToFit() { zoom = .fit }
    func zoomToActualSize() { zoom = .scale(1 / max(backingScale, 1)) }

    private func step(by direction: Int) {
        let current = lastDisplayScale * backingScale
        let next = direction > 0
            ? Self.zoomSteps.first { $0 > current + 0.005 }
            : Self.zoomSteps.last { $0 < current - 0.005 }
        guard let next else { return }
        zoom = .scale(next / max(backingScale, 1))
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

        for annotation in annotations where annotation.id != hiddenMarkID {
            draw(annotation)
        }
        if let preview {
            draw(preview)
        }

        drawDescriptionIfNeeded()
    }

    func renderedImage() -> NSImage? {
        commitPendingEdits?()
        commitPolyline(selecting: false)
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
        if wroteImage { markClean() }
        return wroteImage
    }

    @discardableResult
    func save(to url: URL, copyPath: Bool, overwrite: Bool = true) -> Bool {
        guard let data = pngData() else {
            statusMessage = "QuickShot could not render the annotated screenshot."
            return false
        }

        do {
            try data.write(to: url, options: overwrite ? .atomic : .withoutOverwriting)
            markClean()
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

        case .redact:
            drawRedaction(annotation)

        case .arrow:
            drawArrow(annotation, from: start, to: end, color: color)

        case .line, .polyline:
            let points = annotation.pathPoints.map(translated)
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            let curves = annotation.lineCurves.map { $0.map(translated) }
            if curves.isEmpty { points.dropFirst().forEach { path.line(to: $0) } }
            else { curves.forEach { path.curve(to: $0[3], controlPoint1: $0[1], controlPoint2: $0[2]) } }
            path.lineWidth = annotation.style.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if annotation.style.dashed { path.setLineDash([12, 8], count: 2, phase: 0) }
            color.setStroke()
            path.stroke()

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

    /// The side of one mosaic block, in image pixels. Fine blocks leave text readable,
    /// so the block never drops below 16 and grows with the area covered.
    static func pixelBlockSize(for area: CGSize) -> CGFloat {
        max(16, (min(area.width, area.height) / 3).rounded(.up))
    }

    private func drawRedaction(_ mark: AnnotationMark) {
        let target = mark.bounds
        guard mark.style.pixelate, let mosaic = mosaic(for: target) else {
            mark.style.color.nsColor.withAlphaComponent(1).setFill()
            NSBezierPath(rect: target.offsetBy(dx: imageOrigin.x, dy: imageOrigin.y)).fill()
            return
        }
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.imageInterpolation = .none
        context.cgContext.interpolationQuality = .none
        context.cgContext.draw(mosaic.image, in: mosaic.rect.offsetBy(dx: imageOrigin.x, dy: imageOrigin.y))
        context.restoreGraphicsState()
    }

    /// Averages the covered part of the screenshot into coarse blocks. Returns nil when
    /// the mark lies entirely outside the screenshot.
    private func mosaic(for rect: CGRect) -> (image: CGImage, rect: CGRect)? {
        let covered = rect.intersection(CGRect(origin: .zero, size: image.size))
        guard !covered.isNull, covered.width >= 1, covered.height >= 1,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scaleX = CGFloat(source.width) / image.size.width
        let scaleY = CGFloat(source.height) / image.size.height
        // Marks use a bottom-left origin; the bitmap's rows start at the top.
        let crop = CGRect(x: covered.minX * scaleX, y: (image.size.height - covered.maxY) * scaleY,
                          width: covered.width * scaleX, height: covered.height * scaleY).integral
        guard let patch = source.cropping(to: crop) else { return nil }
        let block = Self.pixelBlockSize(for: covered.size)
        let columns = max(1, Int((covered.width / block).rounded(.up)))
        let rows = max(1, Int((covered.height / block).rounded(.up)))
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        context.draw(patch, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let small = context.makeImage() else { return nil }
        return (small, covered)
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
