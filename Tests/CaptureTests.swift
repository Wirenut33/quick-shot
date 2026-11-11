import AppKit
import Carbon.HIToolbox

@main
struct CaptureTests {
    @MainActor static func main() throws {
        // MARK: Geometry

        let overlay = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        // A drag in any direction gives the same rectangle, kept inside the display.
        let dragged = CaptureGeometry.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), in: overlay)
        precondition(dragged == CGRect(x: 100, y: 50, width: 200, height: 150))
        let escaped = CaptureGeometry.selection(from: CGPoint(x: 1_400, y: 880), to: CGPoint(x: 1_600, y: 1_000), in: overlay)
        precondition(escaped == CGRect(x: 1_400, y: 880, width: 40, height: 20), "A drag past the edge must be clipped: \(escaped)")

        // The same points map to different pixels on a Retina display and a 1× display.
        let retina = CGSize(width: 2_880, height: 1_800)
        precondition(CaptureGeometry.pixelRect(for: dragged, overlaySize: overlay.size, imageSize: retina)
                     == CGRect(x: 200, y: 100, width: 400, height: 300))
        precondition(CaptureGeometry.pixelRect(for: dragged, overlaySize: overlay.size, imageSize: overlay.size) == dragged)
        // Fractional edges snap outward and never leave the image.
        let fractional = CaptureGeometry.pixelRect(for: CGRect(x: 10.25, y: 10.25, width: 10.5, height: 10.5),
                                                   overlaySize: overlay.size, imageSize: retina)
        precondition(fractional == CGRect(x: 20, y: 20, width: 22, height: 22), "\(fractional)")
        let corner = CaptureGeometry.pixelRect(for: CGRect(x: 1_430, y: 890, width: 10, height: 10),
                                               overlaySize: overlay.size, imageSize: retina)
        precondition(corner == CGRect(x: 2_860, y: 1_780, width: 20, height: 20))
        precondition(CaptureGeometry.pixelRect(for: .zero, overlaySize: overlay.size, imageSize: retina) == .zero)
        precondition(CaptureGeometry.pixelRect(for: dragged, overlaySize: .zero, imageSize: retina) == .zero)
        precondition(CaptureGeometry.sizeLabel(for: CGRect(x: 0, y: 0, width: 400, height: 300)) == "400 × 300")

        // A second display to the left and above the primary one has a negative origin.
        let external = CGRect(x: -1_920, y: -180, width: 1_920, height: 1_080)
        let windowOnExternal = CGRect(x: -1_800, y: -100, width: 800, height: 600)
        precondition(CaptureGeometry.overlayRect(for: windowOnExternal, displayFrame: external)
                     == CGRect(x: 120, y: 80, width: 800, height: 600))
        // A window that spans both displays is clipped differently on each.
        let spanning = CGRect(x: -100, y: 100, width: 400, height: 300)
        precondition(CaptureGeometry.overlayRect(for: spanning, displayFrame: overlay).intersection(overlay)
                     == CGRect(x: 0, y: 100, width: 300, height: 300))
        precondition(CaptureGeometry.overlayRect(for: spanning, displayFrame: external).intersection(CGRect(origin: .zero, size: external.size))
                     == CGRect(x: 1_820, y: 280, width: 100, height: 300))
        // Hover picks the frontmost window under the pointer.
        let stack = [CGRect(x: 100, y: 100, width: 200, height: 200), CGRect(x: 0, y: 0, width: 800, height: 600)]
        precondition(CaptureGeometry.frontmostIndex(containing: CGPoint(x: 150, y: 150), in: stack) == 0)
        precondition(CaptureGeometry.frontmostIndex(containing: CGPoint(x: 500, y: 500), in: stack) == 1)
        precondition(CaptureGeometry.frontmostIndex(containing: CGPoint(x: 900, y: 700), in: stack) == nil)

        // MARK: Shortcuts

        let area = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift])
        precondition(area.carbonModifiers == UInt32(cmdKey | shiftKey))
        precondition(area.displayString.hasPrefix("⇧⌘"), "Modifiers must read in the standard order: \(area.displayString)")
        precondition(Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .option, .shift, .command]).displayString == "⌃⌥⇧⌘Space")
        precondition(Shortcut(keyCode: UInt32(kVK_F5), modifiers: []).displayString == "F5")
        precondition(area.isValid && Shortcut(keyCode: UInt32(kVK_F5), modifiers: []).isValid)
        precondition(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: []).isValid && !Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: .shift).isValid,
                     "A bare or shifted letter must never become a global shortcut")
        // Caps Lock and other flags are not part of a shortcut.
        precondition(Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift, .capsLock, .numericPad]) == area)
        precondition(Shortcut(keyCode: UInt32(kVK_Space), modifiers: .command).menuKeyEquivalent == " ")
        precondition(Shortcut(keyCode: UInt32(kVK_F5), modifiers: .command).menuKeyEquivalent == nil)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(area))
        precondition(decoded == area)
        precondition(Set(CaptureAction.allCases.map(\.hotKeyID)).count == CaptureAction.allCases.count)
        precondition(CaptureAction.fullScreen.suggestedShortcut != nil && CaptureAction.text.suggestedShortcut == nil)
        _ = HotKeyCenter.systemReservedShortcuts()

        // MARK: Settings

        let suite = "QuickShotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickShotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // A folder stored as a path by an older version carries over.
        defaults.set(folder.path, forKey: "saveLocation")
        let settings = AppSettings(defaults: defaults)
        precondition(settings.annotateMode && !settings.collectMode && !settings.welcomeCompleted, "Defaults must match a first launch")
        precondition(settings.shortcuts.isEmpty, "No shortcut exists until the user accepts one")
        precondition(settings.saveFolderURL?.standardizedFileURL.path == folder.standardizedFileURL.path && defaults.string(forKey: "saveLocation") == nil)

        settings.setShortcut(area, for: .selection)
        settings.setShortcut(area, for: .window)
        precondition(settings.shortcut(for: .window) == area && settings.shortcut(for: .selection) == nil, "One shortcut must not run two actions")
        settings.annotateMode = false
        settings.welcomeCompleted = true
        var arrow = AnnotationStyle(); arrow.color = .blue; arrow.width = 12
        settings.setToolStyle(arrow, for: AnnotationTool.arrow.rawValue)
        let reloaded = AppSettings(defaults: defaults)
        precondition(reloaded.shortcuts == [.window: area] && !reloaded.annotateMode && reloaded.welcomeCompleted)
        precondition(reloaded.toolStyles() == [AnnotationTool.arrow.rawValue: arrow])
        reloaded.setShortcut(nil, for: .window)
        precondition(AppSettings(defaults: defaults).shortcuts.isEmpty)

        // Quick save writes inside the chosen folder and never replaces a file.
        let first = AppSettings.uniqueFileURL(in: folder, base: "Screenshot_test")
        precondition(first.lastPathComponent == "Screenshot_test.png")
        precondition(reloaded.withSaveFolder { target in
            (try? Data([1]).write(to: AppSettings.uniqueFileURL(in: target, base: "Screenshot_test"), options: .withoutOverwriting)) != nil
        } == true)
        let second = AppSettings.uniqueFileURL(in: folder, base: "Screenshot_test")
        precondition(second.lastPathComponent == "Screenshot_test_2.png", "A second save in the same second must get its own name")
        try Data([2]).write(to: second, options: .withoutOverwriting)
        precondition(AppSettings.uniqueFileURL(in: folder, base: "Screenshot_test").lastPathComponent == "Screenshot_test_3.png")
        let kept = try Data(contentsOf: first)
        precondition((try? Data([3]).write(to: first, options: .withoutOverwriting)) == nil && kept == Data([1]))
        precondition(AppSettings.screenshotBaseName(at: Date(timeIntervalSince1970: 0)).hasPrefix("Screenshot_19"))

        // A folder that has gone away falls back to asking, instead of failing the save.
        try FileManager.default.removeItem(at: folder)
        var ran = false
        precondition(reloaded.withSaveFolder { _ in ran = true } == nil && !ran, "A missing folder must report nil so the save panel is shown")
        reloaded.clearSaveFolder()
        precondition(reloaded.saveFolderURL == nil && AppSettings(defaults: defaults).saveFolderURL == nil)

        // MARK: Text recognition

        let size = NSSize(width: 900, height: 220)
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("Invoice 48213 approved" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [
            .font: NSFont.systemFont(ofSize: 56, weight: .semibold), .foregroundColor: NSColor.black
        ])
        NSGraphicsContext.restoreGraphicsState()
        let text = try TextRecognizer.recognize(rendered.cgImage!)
        precondition(text.contains("48213") && text.lowercased().contains("invoice"), "Recognised: \(text)")

        let blank = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: blank)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        NSGraphicsContext.restoreGraphicsState()
        let nothing = try TextRecognizer.recognize(blank.cgImage!)
        precondition(nothing.isEmpty, "An area without text must give an empty result")

        // Redacted text must not come back out of the exported image.
        let document = AnnotationDocument(image: ScreenshotImage.make(from: rendered.cgImage!))
        document.canvasPadding = 0
        let readable = try TextRecognizer.recognize(document.renderedImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        precondition(readable.contains("48213"))
        document.add(AnnotationMark(kind: .redact, start: CGPoint(x: 20, y: 60), end: CGPoint(x: 880, y: 170), style: AnnotationStyle(color: .black)))
        let redacted = try TextRecognizer.recognize(document.renderedImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        precondition(!redacted.contains("48213") && !redacted.lowercased().contains("invoice"), "Redacted text leaked: \(redacted)")

        print("PASS: mixed-scale capture geometry, shortcut encoding and validation, settings persistence, bookmark fallback, collision-safe names, text recognition, redaction holds against recognition")
    }
}

/// Mirrors the app's convention that an editor image is sized in pixels.
enum ScreenshotImage {
    static func make(from cgImage: CGImage) -> NSImage {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }
}
