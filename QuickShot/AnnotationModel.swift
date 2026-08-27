//
//  AnnotationModel.swift
//  QuickShot
//

import AppKit
import Combine
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, rectangle, arrow, text

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }

    var help: String {
        switch self {
        case .select: return "Select / Move (V)"
        case .rectangle: return "Rectangle (R)"
        case .arrow: return "Arrow (A)"
        case .text: return "Text (T)"
        }
    }
}

/// A single mark on the screenshot. Coordinates are in screenshot points, relative to the
/// screenshot's top-left corner, so marks stay attached to the image when the margin changes.
struct Annotation: Identifiable, Equatable {
    enum Kind: Equatable { case rectangle, arrow, text }

    let id: UUID
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var text: String

    init(kind: Kind, start: CGPoint, end: CGPoint, text: String = "") {
        id = UUID()
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    mutating func move(byX dx: CGFloat, y dy: CGFloat) {
        start.x += dx; start.y += dy
        end.x += dx; end.y += dy
    }
}

enum AnnotationStyle {
    static let red = Color(red: 0.88, green: 0.19, blue: 0.19)
    static let lineWidth: CGFloat = 3
    static let arrowHeadLength: CGFloat = 18
    static let hitSlop: CGFloat = 8

    static let textFontSize: CGFloat = 22
    static let textFont = Font.system(size: textFontSize, weight: .semibold)
    static let textNSFont = NSFont.systemFont(ofSize: textFontSize, weight: .semibold)

    static let descriptionFontSize: CGFloat = 18
    static let descriptionFont = Font.system(size: descriptionFontSize)
    static let descriptionNSFont = NSFont.systemFont(ofSize: descriptionFontSize)
    static let descriptionInset: CGFloat = 24
}

@MainActor
final class AnnotationDocument: ObservableObject {
    let image: NSImage
    let imageSize: CGSize
    /// Pixels per point of the captured image (2 on Retina displays), used so exports keep full resolution.
    let pixelScale: CGFloat

    @Published var annotations: [Annotation] = []
    @Published var margin: CGFloat = 0
    @Published var descriptionText = ""
    @Published var tool: AnnotationTool = .arrow
    @Published var selectedID: UUID?
    @Published var editingTextID: UUID?
    @Published private(set) var undoStack: [[Annotation]] = []

    private var textEditSnapshot: [Annotation]?

    init(image: NSImage) {
        self.image = image
        imageSize = image.size
        if let rep = image.representations.first, rep.pixelsWide > 0, image.size.width > 0 {
            pixelScale = max(1, CGFloat(rep.pixelsWide) / image.size.width)
        } else {
            pixelScale = 1
        }
    }

    // MARK: - Geometry (canvas coordinates)

    var contentWidth: CGFloat { imageSize.width + margin * 2 }
    var contentHeight: CGFloat { imageSize.height + margin * 2 }

    var hasDescription: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var descriptionBandHeight: CGFloat {
        guard hasDescription else { return 0 }
        let inset = AnnotationStyle.descriptionInset
        let width = max(contentWidth - inset * 2, 40)
        let measured = NSAttributedString(string: descriptionText,
                                          attributes: [.font: AnnotationStyle.descriptionNSFont])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        // Slack so SwiftUI's slightly different line layout never clips the last line.
        return ceil(measured.height) + inset * 2 + AnnotationStyle.descriptionFontSize
    }

    var canvasSize: CGSize {
        CGSize(width: contentWidth, height: contentHeight + descriptionBandHeight)
    }

    // MARK: - Lookup / hit testing (screenshot coordinates)

    func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    func annotation(with id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func bounds(of annotation: Annotation) -> CGRect {
        switch annotation.kind {
        case .rectangle, .arrow:
            return annotation.rect
        case .text:
            let string = annotation.text.isEmpty ? "Text" : annotation.text
            let size = NSAttributedString(string: string, attributes: [.font: AnnotationStyle.textNSFont]).size()
            return CGRect(origin: annotation.start, size: CGSize(width: ceil(size.width), height: ceil(size.height)))
        }
    }

    func hitTest(_ point: CGPoint) -> UUID? {
        let slop = AnnotationStyle.hitSlop
        for annotation in annotations.reversed() {
            switch annotation.kind {
            case .rectangle:
                // Rectangles are hollow, so only their outline is selectable; this keeps
                // things inside a box reachable.
                let outer = annotation.rect.insetBy(dx: -slop, dy: -slop)
                let inner = annotation.rect.insetBy(dx: slop, dy: slop)
                if outer.contains(point) && (inner.isNull || !inner.contains(point)) {
                    return annotation.id
                }
            case .text:
                if bounds(of: annotation).insetBy(dx: -slop, dy: -slop).contains(point) {
                    return annotation.id
                }
            case .arrow:
                if Self.distance(from: point, toSegment: annotation.start, annotation.end) <= slop {
                    return annotation.id
                }
            }
        }
        return nil
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - projection.x, p.y - projection.y)
    }

    // MARK: - Mutation

    var canUndo: Bool { !undoStack.isEmpty }

    func pushUndo(_ snapshot: [Annotation]? = nil) {
        undoStack.append(snapshot ?? annotations)
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        editingTextID = nil
        textEditSnapshot = nil
        annotations = previous
        if let selected = selectedID, index(of: selected) == nil {
            selectedID = nil
        }
    }

    func deleteSelected() {
        guard let id = selectedID, let idx = index(of: id) else { return }
        pushUndo()
        annotations.remove(at: idx)
        selectedID = nil
        if editingTextID == id { editingTextID = nil }
    }

    func clearAll() {
        guard !annotations.isEmpty else { return }
        pushUndo()
        annotations.removeAll()
        selectedID = nil
        editingTextID = nil
    }

    // MARK: - Text editing

    func beginTextEditing(at point: CGPoint) {
        finishTextEditing()
        textEditSnapshot = annotations
        let annotation = Annotation(kind: .text, start: point, end: point)
        annotations.append(annotation)
        selectedID = annotation.id
        editingTextID = annotation.id
    }

    func beginTextEditing(id: UUID) {
        guard let existing = annotation(with: id), existing.kind == .text else { return }
        finishTextEditing()
        textEditSnapshot = annotations
        selectedID = id
        editingTextID = id
    }

    /// Ends the in-place text edit. Empty or cancelled edits restore the pre-edit state
    /// (which drops a brand-new empty label); real changes become an undo step.
    func finishTextEditing(cancel: Bool = false) {
        guard let id = editingTextID else { return }
        editingTextID = nil
        let snapshot = textEditSnapshot
        textEditSnapshot = nil
        guard let idx = index(of: id) else { return }

        let trimmed = annotations[idx].text.trimmingCharacters(in: .whitespaces)
        if cancel || trimmed.isEmpty {
            if let snapshot {
                annotations = snapshot
            } else {
                annotations.remove(at: idx)
            }
            if index(of: id) == nil, selectedID == id {
                selectedID = nil
            }
        } else if let snapshot, snapshot != annotations {
            pushUndo(snapshot)
        }
    }

    // MARK: - Drawing

    /// Draws the full canvas (screenshot, margin, marks, description band) in canvas coordinates.
    /// Used by both the live editor and the exporter so what you see is what gets copied.
    func draw(in context: inout GraphicsContext, showSelection: Bool) {
        context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))

        if hasDescription {
            let bandTop = contentHeight
            var separator = Path()
            separator.move(to: CGPoint(x: 0, y: bandTop))
            separator.addLine(to: CGPoint(x: contentWidth, y: bandTop))
            context.stroke(separator, with: .color(Color(white: 0.85)), lineWidth: 1)

            let inset = AnnotationStyle.descriptionInset
            let textRect = CGRect(x: inset, y: bandTop + inset,
                                  width: contentWidth - inset * 2,
                                  height: descriptionBandHeight - inset * 2)
            let text = Text(descriptionText)
                .font(AnnotationStyle.descriptionFont)
                .foregroundStyle(Color(white: 0.12))
            context.draw(text, in: textRect)
        }

        context.translateBy(x: margin, y: margin)

        let imageRect = CGRect(origin: .zero, size: imageSize)
        context.draw(Image(nsImage: image), in: imageRect)
        if margin > 0 {
            context.stroke(Path(imageRect), with: .color(Color(white: 0.8)), lineWidth: 1)
        }

        for annotation in annotations where annotation.id != editingTextID {
            draw(annotation, in: &context)
        }

        if showSelection, let id = selectedID, let selected = annotation(with: id) {
            let box = bounds(of: selected).insetBy(dx: -6, dy: -6)
            context.stroke(Path(roundedRect: box, cornerRadius: 4),
                           with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: AnnotationStyle.lineWidth, lineCap: .round, lineJoin: .round)
        switch annotation.kind {
        case .rectangle:
            context.stroke(Path(roundedRect: annotation.rect, cornerRadius: 3),
                           with: .color(AnnotationStyle.red), style: stroke)
        case .arrow:
            var path = Path()
            path.move(to: annotation.start)
            path.addLine(to: annotation.end)
            let dx = annotation.end.x - annotation.start.x
            let dy = annotation.end.y - annotation.start.y
            if hypot(dx, dy) > 1 {
                let angle = atan2(dy, dx)
                let length = AnnotationStyle.arrowHeadLength
                let spread = CGFloat.pi / 7
                let left = CGPoint(x: annotation.end.x - length * cos(angle - spread),
                                   y: annotation.end.y - length * sin(angle - spread))
                let right = CGPoint(x: annotation.end.x - length * cos(angle + spread),
                                    y: annotation.end.y - length * sin(angle + spread))
                path.move(to: left)
                path.addLine(to: annotation.end)
                path.addLine(to: right)
            }
            context.stroke(path, with: .color(AnnotationStyle.red), style: stroke)
        case .text:
            let text = Text(annotation.text)
                .font(AnnotationStyle.textFont)
                .foregroundStyle(AnnotationStyle.red)
            context.draw(text, at: annotation.start, anchor: .topLeading)
        }
    }
}
