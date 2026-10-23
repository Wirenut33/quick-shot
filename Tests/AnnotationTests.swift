import AppKit

@main
struct AnnotationTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let image = NSImage(size: NSSize(width: 400, height: 300))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 400, height: 300).fill(); image.unlockFocus()
        let doc = AnnotationDocument(image: image)
        let canvas = AnnotationCanvasNSView(document: doc, displayScale: 1)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 472, height: 372), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x + 36, y: point.y + 36), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func click(_ point: CGPoint, clicks: Int = 1) {
            canvas.mouseDown(with: event(.leftMouseDown, point, clicks: clicks))
            canvas.mouseUp(with: event(.leftMouseUp, point, clicks: clicks))
        }
        func key(_ code: UInt16) {
            canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
        }
        func drag(_ start: CGPoint, _ end: CGPoint) {
            canvas.mouseDown(with: event(.leftMouseDown, start))
            canvas.mouseDragged(with: event(.leftMouseDragged, end))
            canvas.mouseUp(with: event(.leftMouseUp, end))
        }
        doc.selectedTool = .arrow
        drag(CGPoint(x: 40, y: 50), CGPoint(x: 300, y: 50))
        precondition(doc.annotations.count == 1 && doc.selectedTool == .select)
        let arrow = doc.annotations[0]
        drag(arrow.midpoint, CGPoint(x: 170, y: 140))
        let curved = doc.annotations[0]
        precondition(curved.point(at: 0.5) == CGPoint(x: 170, y: 140), "Arrow middle must follow drag exactly")
        precondition(curved.start == arrow.start && curved.end == arrow.end, "Bending must preserve endpoints")
        precondition(curved.contains(CGPoint(x: 170, y: 140), tolerance: 5))
        precondition(!curved.contains(CGPoint(x: 170, y: 50), tolerance: 5), "Hit testing must follow the curve, not its bounding box")
        doc.undo(); precondition(doc.annotations[0] == arrow, "One undo must reverse the whole bend gesture")
        doc.redo(); precondition(doc.annotations[0] == curved)
        doc.select(curved.id)
        // Move from a point on the shaft away from all three handles.
        let shaft = curved.point(at: 0.25)
        drag(shaft, CGPoint(x: shaft.x + 20, y: shaft.y + 15))
        precondition(doc.annotations[0].midpoint == CGPoint(x: 190, y: 155), "Move must translate the bend too")
        doc.undo()
        doc.select(curved.id)
        drag(curved.end, CGPoint(x: 330, y: 80))
        precondition(doc.annotations[0].end == CGPoint(x: 330, y: 80))
        doc.undo()
        doc.selectedTool = .rectangle
        drag(CGPoint(x: 20,y: 180), CGPoint(x: 120,y: 240))
        drag(CGPoint(x: 120,y: 240), CGPoint(x: 160,y: 270))
        precondition(doc.annotations.last!.bounds.size == CGSize(width: 140,height: 90), "Corner drag must resize")
        var style = doc.style; style.width = 12; style.dashed = true; style.color = .blue
        doc.applyStyle(style)
        precondition(doc.annotations.last!.style == style)
        doc.undo(); precondition(doc.annotations.last!.style != style)
        doc.selectedTool = .text; doc.textDraft = "Before"
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 30,y: 100)))
        doc.textDraft = "After"; doc.updateText()
        style = doc.style; style.fontSize = 48; style.bold = false; doc.applyStyle(style)
        precondition(doc.selectedMark!.kind == .text("After") && doc.selectedMark!.style.fontSize == 48 && !doc.selectedMark!.style.bold)
        doc.clear(); precondition(doc.annotations.isEmpty)
        doc.undo(); precondition(doc.annotations.count == 3, "Clear must be undoable")
        doc.select(doc.annotations.last!.id); doc.deleteSelected(); precondition(doc.annotations.count == 2)
        doc.undo(); precondition(doc.annotations.count == 3)
        doc.undo(); doc.add(AnnotationMark(kind: .rectangle, start: .zero, end: CGPoint(x: 5,y: 5)))
        precondition(!doc.canRedo, "New edit must invalidate redo")
        // Exercise actual export: highlight blends over underlying pixels.
        let highlight = AnnotationDocument(image: image)
        highlight.add(AnnotationMark(kind: .highlight, start: CGPoint(x: 20,y: 20), end: CGPoint(x: 100,y: 100), style: AnnotationStyle(color: .yellow)))
        let png = highlight.pngData()!
        let bitmap = NSBitmapImageRep(data: png)!
        let sample = bitmap.colorAt(x: 86, y: bitmap.pixelsHigh - 86)!.usingColorSpace(.deviceRGB)!
        precondition(sample.redComponent > 0.8 && sample.greenComponent > 0.8 && sample.blueComponent > 0.5 && sample.blueComponent < 0.95, "Highlight must be translucent and retain screenshot content")
        precondition(doc.pngData() != nil, "Styled curved arrows and text must export")
        // Straight line: drag to draw, endpoints are handles, hit testing follows the segment.
        let lines = AnnotationDocument(image: image)
        canvas.document = lines
        lines.selectedTool = .line
        drag(CGPoint(x: 40, y: 40), CGPoint(x: 240, y: 240))
        let line = lines.annotations[0]
        precondition(line.kind == .line && lines.selectedTool == .select && lines.selectedID == line.id)
        precondition(line.contains(CGPoint(x: 140, y: 140), tolerance: 5) && !line.contains(CGPoint(x: 200, y: 60), tolerance: 5), "Line hit testing must follow the segment")
        drag(line.end, CGPoint(x: 300, y: 100))
        precondition(lines.annotations[0].start == line.start && lines.annotations[0].end == CGPoint(x: 300, y: 100), "Dragging a line end must move only that end")
        lines.undo(); precondition(lines.annotations[0] == line)
        // Polyline: clicks add points, a press-drag lays down a segment, double-click finishes.
        lines.selectedTool = .polyline
        click(CGPoint(x: 20, y: 200))
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 100, y: 200)))
        canvas.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 120, y: 260)))
        canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 120, y: 260)))
        click(CGPoint(x: 200, y: 200))
        click(CGPoint(x: 200, y: 200), clicks: 2)
        let poly = lines.annotations.last!
        precondition(poly.kind == .polyline && poly.points == [CGPoint(x: 20, y: 200), CGPoint(x: 100, y: 200), CGPoint(x: 120, y: 260), CGPoint(x: 200, y: 200)], "Polyline points: \(poly.points)")
        precondition(lines.polylineDraft.isEmpty && lines.selectedTool == .select && lines.selectedID == poly.id)
        precondition(poly.start == poly.points.first && poly.end == poly.points.last)
        precondition(poly.contains(CGPoint(x: 60, y: 200), tolerance: 5) && !poly.contains(CGPoint(x: 160, y: 120), tolerance: 5))
        drag(CGPoint(x: 100, y: 200), CGPoint(x: 100, y: 150))
        precondition(lines.annotations.last!.points[1] == CGPoint(x: 100, y: 150) && lines.annotations.last!.points[2] == poly.points[2], "Dragging a vertex must move only that vertex")
        lines.undo(); lines.select(poly.id)
        drag(CGPoint(x: 60, y: 200), CGPoint(x: 70, y: 210))
        precondition(lines.annotations.last!.points == poly.points.map { CGPoint(x: $0.x + 10, y: $0.y + 10) }, "Move must translate every vertex")
        lines.undo(); precondition(lines.annotations.count == 2)
        // Return finishes, Delete drops the last point, Escape cancels, and switching tools keeps the draft.
        lines.selectedTool = .polyline
        click(CGPoint(x: 10, y: 10)); click(CGPoint(x: 50, y: 10)); click(CGPoint(x: 90, y: 10))
        key(51); precondition(lines.polylineDraft.count == 2, "Delete must remove the last draft point")
        key(36); precondition(lines.annotations.last!.points == [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 10)])
        lines.undo()
        lines.selectedTool = .polyline
        click(CGPoint(x: 10, y: 10)); click(CGPoint(x: 50, y: 10))
        key(53); precondition(lines.polylineDraft.isEmpty && lines.annotations.count == 2, "Escape must cancel the draft")
        click(CGPoint(x: 10, y: 10))
        canvas.mouseDown(with: event(.leftMouseDown, CGPoint(x: 50, y: 10)))
        key(53); canvas.mouseUp(with: event(.leftMouseUp, CGPoint(x: 90, y: 10)))
        precondition(lines.polylineDraft.isEmpty, "Releasing after Escape must not start a new draft")
        click(CGPoint(x: 10, y: 10)); click(CGPoint(x: 10, y: 10), clicks: 2)
        precondition(lines.annotations.count == 2 && lines.selectedTool == .polyline, "A single point is not a line")
        click(CGPoint(x: 10, y: 10)); click(CGPoint(x: 50, y: 10))
        lines.selectedTool = .rectangle
        precondition(lines.annotations.count == 3 && lines.selectedTool == .rectangle, "Switching tools must keep the line and the chosen tool")
        lines.selectedTool = .polyline
        click(CGPoint(x: 300, y: 20)); click(CGPoint(x: 380, y: 20))
        var thick = lines.style; thick.width = 12; thick.color = .blue; lines.style = thick
        let exported = NSBitmapImageRep(data: lines.pngData()!)!
        precondition(lines.annotations.count == 4 && lines.polylineDraft.isEmpty, "Export must include an in-progress polyline")
        let stroke = exported.colorAt(x: 36 + 340, y: exported.pixelsHigh - (36 + 20))!.usingColorSpace(.deviceRGB)!
        precondition(stroke.blueComponent > 0.8 && stroke.redComponent < 0.3, "Polyline must export with its style")
        print("PASS: canvas draw/select/move/resize/bend, lines and polylines, text styling, edit undo/redo, highlight export")
    }
}
