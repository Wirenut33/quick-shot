//
//  ScreenshotManager.swift
//  QuickShot
//

import AppKit

class ScreenshotManager {

    enum CaptureKind {
        case fullScreen, selection, window

        fileprivate var arguments: [String] {
            switch self {
            case .fullScreen: return []
            case .selection: return ["-s"]
            case .window: return ["-w"]
            }
        }
    }

    private static let copyPathModeKey = "copyPathMode"
    private static let annotateModeKey = "annotateMode"
    private static let saveLocationKey = "saveLocation"

    var copyPathMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.copyPathModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.copyPathModeKey)
            UserDefaults.standard.synchronize()
        }
    }

    var annotateMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.annotateModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.annotateModeKey)
            UserDefaults.standard.synchronize()
        }
    }

    var saveLocation: URL? {
        get {
            if let path = UserDefaults.standard.string(forKey: Self.saveLocationKey) {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: Self.saveLocationKey)
            UserDefaults.standard.synchronize()
        }
    }

    var saveLocationName: String {
        if let location = saveLocation {
            return location.lastPathComponent
        }
        return "Desktop"
    }

    func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermissionIfNeeded() -> Bool {
        if hasScreenRecordingPermission() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    private func generateFilePath() -> String {
        let folder = saveLocation ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return folder.appendingPathComponent("Screenshot_\(timestamp).png").path
    }

    private func copyPathToClipboard(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func captureFullScreen() {
        capture(.fullScreen)
    }

    func captureSelection() {
        capture(.selection)
    }

    func captureWindow() {
        capture(.window)
    }

    func capture(_ kind: CaptureKind) {
        guard requestScreenRecordingPermissionIfNeeded() else { return }

        if annotateMode {
            captureForAnnotation(kind)
        } else if copyPathMode {
            let path = generateFilePath()
            runScreencapture(["-x"] + kind.arguments + [path]) { [weak self] in
                if FileManager.default.fileExists(atPath: path) {
                    self?.copyPathToClipboard(path)
                }
            }
        } else {
            runScreencapture(["-c", "-x"] + kind.arguments)
        }
    }

    private func captureForAnnotation(_ kind: CaptureKind) {
        let tempPath = NSTemporaryDirectory() + "QuickShot-\(UUID().uuidString).png"
        runScreencapture(["-x"] + kind.arguments + [tempPath]) { [weak self] in
            // No file means the user cancelled the capture (e.g. pressed Escape).
            guard let image = NSImage(contentsOfFile: tempPath) else { return }
            try? FileManager.default.removeItem(atPath: tempPath)

            DispatchQueue.main.async {
                guard let self else { return }
                let title = self.copyPathMode ? "Save & Copy Path" : "Copy to Clipboard"
                AnnotationWindowController.shared.present(image: image, finishTitle: title) { [weak self] edited in
                    self?.deliver(edited)
                }
            }
        }
    }

    /// Hands a finished (annotated) image off the same way a plain capture would:
    /// to the clipboard, or saved to the chosen folder with its path copied.
    private func deliver(_ image: NSImage) {
        guard let png = AnnotationExporter.pngData(from: image) else { return }

        if copyPathMode {
            let path = generateFilePath()
            do {
                try png.write(to: URL(fileURLWithPath: path))
                copyPathToClipboard(path)
            } catch {
                NSLog("QuickShot: failed to save annotated screenshot: \(error)")
            }
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            if let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }

    private func runScreencapture(_ arguments: [String], completion: (() -> Void)? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments
        if let completion {
            task.terminationHandler = { _ in completion() }
        }
        do {
            try task.run()
        } catch {
            NSLog("QuickShot: failed to launch screencapture: \(error)")
        }
    }
}
