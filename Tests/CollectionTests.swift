import AppKit

@main
struct CollectionTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let collection = SnapshotCollection(directory: directory)
        func image(_ color: NSColor) -> NSImage {
            let image = NSImage(size: NSSize(width: 80, height: 40))
            image.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 80, height: 40).fill()
            image.unlockFocus()
            return image
        }
        precondition(collection.add(image(.red)))
        precondition(collection.add(image(.blue)))
        precondition(collection.snapshots.count == 2)
        let restored = SnapshotCollection(directory: directory)
        precondition(restored.snapshots == collection.snapshots, "Collection must survive restart")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        precondition(restored.copy(restored.snapshots, to: board))
        precondition(board.pasteboardItems?.count == 2, "Must expose two pasteboard items")
        for item in board.pasteboardItems! {
            precondition(item.data(forType: .png) != nil && item.data(forType: .tiff) != nil)
            precondition(item.string(forType: .fileURL) != nil)
        }
        precondition(restored.copyCombined(restored.snapshots, to: board))
        let combined = NSBitmapImageRep(data: board.data(forType: .png)!)!
        precondition(combined.pixelsWide == 80 && combined.pixelsHigh == 104)
        precondition(board.pasteboardItems?.count == 1)
        let count = board.changeCount
        precondition(!restored.copy([], to: board))
        let missing = SavedSnapshot(url: directory.appendingPathComponent("missing.png"))
        precondition(!restored.copy([restored.snapshots[0], missing], to: board))
        precondition(board.changeCount == count, "Failed copies must preserve clipboard")
        print("PASS: persistence, two image/file attachments, combined dimensions, empty/missing-file clipboard preservation")
    }
}
