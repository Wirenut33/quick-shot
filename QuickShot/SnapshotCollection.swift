import AppKit
import SwiftUI
import Combine

struct SavedSnapshot: Identifiable, Hashable {
    let url: URL
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// PNG files are the source of truth, so a restart never loses the collection.
final class SnapshotCollection: ObservableObject {
    @Published private(set) var snapshots: [SavedSnapshot] = []
    @Published var message = "Collect captures, then copy them together and paste into your app."
    let directory: URL
    var onChange: (() -> Void)?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickShot/Snapshots", isDirectory: true)
        reload()
    }

    private func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            snapshots = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { SavedSnapshot(url: $0) }
        } catch { message = "Could not load snapshots: \(error.localizedDescription)" }
        onChange?()
    }

    @discardableResult
    func add(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            message = "Could not prepare this snapshot."; return false
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let url = directory.appendingPathComponent("Snapshot_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(8)).png")
        do {
            try data.write(to: url, options: .atomic)
            reload()
            message = "Saved \(snapshots.count) snapshots. Keep capturing or copy your selection."
            return true
        } catch { message = "Could not save snapshot: \(error.localizedDescription)"; return false }
    }

    func selected(_ ids: Set<String>) -> [SavedSnapshot] {
        snapshots.filter { ids.contains($0.id) }
    }

    @discardableResult
    func copy(_ items: [SavedSnapshot], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !items.isEmpty else { return false }
        // Each item provides both a file URL (multi-attachment consumers) and image data.
        // Prepare every item before touching the clipboard; never silently copy a partial batch.
        var objects: [NSPasteboardItem] = []
        for snapshot in items {
            guard let data = try? Data(contentsOf: snapshot.url), let bitmap = NSBitmapImageRep(data: data),
                  let tiff = bitmap.tiffRepresentation else {
                message = "Could not read \(snapshot.title). Nothing was copied."; return false
            }
            let item = NSPasteboardItem()
            item.setString(snapshot.url.absoluteString, forType: .fileURL)
            item.setData(data, forType: .png)
            item.setData(tiff, forType: .tiff)
            objects.append(item)
        }
        pasteboard.clearContents()
        let success = pasteboard.writeObjects(objects)
        message = success ? "Copied \(items.count) snapshots. Switch to your app and press ⌘V." : "Copy failed. Try again."
        return success
    }

    @discardableResult
    func copyCombined(_ items: [SavedSnapshot], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !items.isEmpty else { return false }
        let images = items.compactMap { NSImage(contentsOf: $0.url) }
        guard images.count == items.count else { message = "Could not read every snapshot."; return false }
        // Bound memory and output dimensions for large batches, preserving aspect ratio.
        let widths = images.map { min($0.size.width, 2400) }
        let heights = zip(images, widths).map { $0.size.height * $1 / $0.size.width }
        let rawWidth = widths.max() ?? 1
        let rawHeight = heights.reduce(0, +) + CGFloat(max(0, images.count - 1)) * 24
        let scale = min(1, 16000 / rawHeight, sqrt(32_000_000 / (rawWidth * rawHeight)))
        let width = max(1, Int(rawWidth * scale)), height = max(1, Int(rawHeight * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        var y = CGFloat(height)
        for (index, image) in images.enumerated() {
            let h = heights[index] * scale
            y -= h
            image.draw(in: NSRect(x: 0, y: y, width: widths[index] * scale, height: h))
            y -= 24 * scale
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]), let tiff = bitmap.tiffRepresentation else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([item])
        message = success ? "Copied \(items.count) snapshots as one image. Press ⌘V in your app." : "Copy failed."
        return success
    }

    func remove(_ items: [SavedSnapshot]) {
        do {
            for item in items { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
            message = "Moved \(items.count) snapshots to Trash."
        } catch { message = "Could not remove snapshot: \(error.localizedDescription)" }
        reload()
    }
}

struct SnapshotCollectionView: View {
    @ObservedObject var collection: SnapshotCollection
    @State private var selection: Set<String> = []
    let annotate: (NSImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snapshot Collection").font(.title2.bold())
            Text("Enable Collect Snapshots in the menu bar, then capture as many examples as you need. Saved snapshots stay here until you remove them.")
                .foregroundStyle(.secondary)
            List(collection.snapshots, selection: $selection) { snapshot in
                HStack(spacing: 12) {
                    SnapshotThumbnail(url: snapshot.url)
                    Text(snapshot.title).lineLimit(1)
                    Spacer()
                    Button("Annotate") {
                        if let image = NSImage(contentsOf: snapshot.url) { annotate(image) }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                .tag(snapshot.id)
            }
            .overlay {
                if collection.snapshots.isEmpty {
                    ContentUnavailableView("No snapshots yet", systemImage: "photo.stack", description: Text("Turn on Collect Snapshots, then use any capture command."))
                }
            }
            HStack {
                Button("Select All") { selection = Set(collection.snapshots.map(\.id)) }
                Button("Show Folder") { NSWorkspace.shared.open(collection.directory) }
                Button("Remove") { collection.remove(collection.selected(selection)); selection = [] }
                    .disabled(selection.isEmpty)
                Spacer()
                Text("\(selection.count) selected")
                Button("Copy as One Image") { _ = collection.copyCombined(collection.selected(selection)) }
                    .disabled(selection.isEmpty)
                Button("Copy Selected") { _ = collection.copy(collection.selected(selection)) }
                    .disabled(selection.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("c", modifiers: .command)
            }
            Text(collection.message).font(.callout).foregroundStyle(.secondary)
            Text("⌘-click or Shift-click to select several. If an app pastes only one attachment, use Copy as One Image.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 850, minHeight: 480)
        .onAppear { selection = Set(collection.snapshots.map(\.id)) }
    }
}

private struct SnapshotThumbnail: View {
    let url: URL
    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 120, height: 76)
        }
    }
}

final class SnapshotCollectionWindowController: NSWindowController {
    init(collection: SnapshotCollection, annotate: @escaping (NSImage) -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "QuickShot — Snapshot Collection"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SnapshotCollectionView(collection: collection, annotate: annotate))
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
