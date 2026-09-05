//
//  ScreenshotManager.swift
//  QuickShot
//

import AppKit

enum CaptureMode {
    case fullScreen
    case selection
    case window

    var arguments: [String] {
        switch self {
        case .fullScreen:
            return []
        case .selection:
            return ["-s"]
        case .window:
            return ["-w"]
        }
    }

    var isInteractive: Bool {
        switch self {
        case .fullScreen:
            return false
        case .selection, .window:
            return true
        }
    }
}

enum ScreenshotError: LocalizedError {
    case cancelled
    case permissionRequired
    case captureFailed(String)
    case invalidImage

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
        }
    }
}

final class ScreenshotManager {
    private static let annotateModeKey = "annotateMode"
    private static let copyPathModeKey = "copyPathMode"
    private static let saveLocationKey = "saveLocation"

    var annotateMode: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.annotateModeKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.annotateModeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.annotateModeKey) }
    }

    var copyPathMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.copyPathModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.copyPathModeKey) }
    }

    var saveLocation: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: Self.saveLocationKey) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set { UserDefaults.standard.set(newValue?.path, forKey: Self.saveLocationKey) }
    }

    var saveLocationName: String {
        saveLocation?.lastPathComponent ?? "Desktop"
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func capture(_ mode: CaptureMode, completion: @escaping (Result<NSImage, Error>) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickShot-\(UUID().uuidString)")
            .appendingPathExtension("png")

        let errorPipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x"] + mode.arguments + [outputURL.path]
        task.standardError = errorPipe

        task.terminationHandler = { process in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(at: outputURL) }

                // A cancelled interactive capture exits without producing a file.
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: outputURL.path) else {
                    let error: Error
                    if mode.isInteractive && detail.isEmpty {
                        error = ScreenshotError.cancelled
                    } else if !self.hasScreenRecordingPermission() {
                        // Use preflight only as a diagnostic after a real
                        // capture failure. It can be stale after replacing a
                        // locally built app, so it must not block the attempt.
                        error = ScreenshotError.permissionRequired
                    } else {
                        error = ScreenshotError.captureFailed(detail)
                    }
                    completion(.failure(error))
                    return
                }

                guard let data = try? Data(contentsOf: outputURL),
                      let bitmap = NSBitmapImageRep(data: data) else {
                    completion(.failure(ScreenshotError.invalidImage))
                    return
                }
                let pixelSize = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
                bitmap.size = pixelSize
                let image = NSImage(size: pixelSize)
                image.addRepresentation(bitmap)
                completion(.success(image))
            }
        }

        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(error))
        }
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

    func suggestedSaveURL() -> URL {
        let folder = saveLocation
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return folder
            .appendingPathComponent("Screenshot_\(formatter.string(from: Date()))")
            .appendingPathExtension("png")
    }
}
