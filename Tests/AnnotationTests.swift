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
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x + 36, y: point.y + 36), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
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
        print("PASS: canvas draw/select/move/resize/bend, text styling, edit undo/redo, highlight export")
    }
}
