//
//  ScreenshotManager.swift
//  QuickShot
//

import AppKit
import ScreenCaptureKit

enum ScreenshotError: LocalizedError {
    case cancelled
    case permissionRequired
    case captureFailed(String)
    case invalidImage
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Capture cancelled."
        case .permissionRequired:
            return "QuickShot needs Screen Recording access before it can capture your screen."
        case .captureFailed(let detail):
            return detail.isEmpty ? "The screenshot could not be captured." : detail
        case .invalidImage:
            return "The screenshot was captured, but QuickShot could not open the image."
        case .noDisplay:
            return "QuickShot could not find a display to capture."
        }
    }
}

enum CaptureOutput {
    case image(NSImage)
    case text(String)
}

/// Runs one capture from start to finish: freeze the screen, let the user choose, and
/// return an image or recognised text.
@MainActor
final class ScreenshotManager {
    /// The selection overlay, while one is on screen.
    private(set) var overlay: SelectionOverlayController?

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func capture(_ action: CaptureAction) async throws -> CaptureOutput {
        let content = try await CaptureEngine.shareableContent()

        if action == .fullScreen {
            guard let display = CaptureEngine.display(underPointerIn: content) else { throw ScreenshotError.noDisplay }
            return .image(Self.image(from: try await CaptureEngine.capture(display).image))
        }

        guard !content.displays.isEmpty else { throw ScreenshotError.noDisplay }
        let displays = try await CaptureEngine.captureAll(content.displays)
        let controller = SelectionOverlayController(
            displays: displays,
            windows: action == .text ? [] : CaptureEngine.windowCandidates(in: content),
            mode: action == .window ? .window : .area,
            areaHint: action == .text ? "Drag over the text to copy" : "Drag to select an area"
        )
        overlay = controller
        defer { overlay = nil }

        switch await controller.run() {
        case .cancelled, .region:
            throw ScreenshotError.cancelled
        case .area(let image):
            if action == .text {
                return .text(try await TextRecognizer.recognizeInBackground(image))
            }
            return .image(Self.image(from: image))
        case .window(let candidate, let fallback):
            do {
                return .image(Self.image(from: try await CaptureEngine.capture(candidate.window)))
            } catch {
                // The window may have closed since the screen was frozen.
                guard let fallback else { throw error }
                return .image(Self.image(from: fallback))
            }
        }
    }

    /// The editor works in pixels, so the image's size is its pixel size.
    static func image(from cgImage: CGImage) -> NSImage {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    @discardableResult
    func copyToClipboard(_ image: NSImage) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiffData, forType: .tiff)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    @discardableResult
    func copyToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
