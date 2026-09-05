//
//  AnnotationDocument.swift
//  QuickShot
//

import AppKit
import Combine

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle = "Rectangle"
    case arrow = "Arrow"
    case text = "Text"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }
}

struct AnnotationMark {
    enum Kind {
        case rectangle
        case arrow
        case text(String)
    }

    let kind: Kind
    let start: CGPoint
    let end: CGPoint
}

final class AnnotationDocument: ObservableObject {
    let image: NSImage

    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var annotations: [AnnotationMark] = []
    @Published var textDraft = ""
    @Published var descriptionText = ""
    @Published var canvasPadding: CGFloat = 36
    @Published var statusMessage = "Draw a rectangle, arrow, or text annotation in red."

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
        annotations.append(mark)
        statusMessage = "Annotation added."
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        statusMessage = "Last annotation removed."
    }

    func clear() {
        annotations.removeAll()
        statusMessage = "Annotations cleared."
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
        let color = NSColor.systemRed

        switch annotation.kind {
        case .rectangle:
            let rect = NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            color.setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 6
            path.stroke()

        case .arrow:
            drawArrow(from: start, to: end, color: color)

        case .text(let text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: color,
                .strokeColor: NSColor.white,
                .strokeWidth: -2.5
            ]
            (text as NSString).draw(at: start, withAttributes: attributes)
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let line = NSBezierPath()
        line.move(to: start)
        line.line(to: end)
        line.lineWidth = 6
        line.lineCapStyle = .round
        color.setStroke()
        line.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 26
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
        head.lineWidth = 6
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
