//
//  ScreenshotManager.swift
//  QuickShot
//

import AppKit

class ScreenshotManager {

    private static let copyPathModeKey = "copyPathMode"
    private static let saveLocationKey = "saveLocation"

    var copyPathMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.copyPathModeKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.copyPathModeKey)
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
        guard requestScreenRecordingPermissionIfNeeded() else { return }
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"

        if copyPathMode {
            let path = generateFilePath()
            task.arguments = ["-x", path]
            task.terminationHandler = { [weak self] _ in
                if FileManager.default.fileExists(atPath: path) {
                    self?.copyPathToClipboard(path)
                }
            }
        } else {
            task.arguments = ["-c", "-x"]
        }
        task.launch()
    }

    func captureSelection() {
        guard requestScreenRecordingPermissionIfNeeded() else { return }
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"

        if copyPathMode {
            let path = generateFilePath()
            task.arguments = ["-x", "-s", path]
            task.terminationHandler = { [weak self] _ in
                if FileManager.default.fileExists(atPath: path) {
                    self?.copyPathToClipboard(path)
                }
            }
        } else {
            task.arguments = ["-c", "-x", "-s"]
        }
        task.launch()
    }

    func captureWindow() {
        guard requestScreenRecordingPermissionIfNeeded() else { return }
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"

        if copyPathMode {
            let path = generateFilePath()
            task.arguments = ["-x", "-w", path]
            task.terminationHandler = { [weak self] _ in
                if FileManager.default.fileExists(atPath: path) {
                    self?.copyPathToClipboard(path)
                }
            }
        } else {
            task.arguments = ["-c", "-x", "-w"]
        }
        task.launch()
    }
}
