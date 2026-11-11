//
//  AppSettings.swift
//  QuickShot
//

import AppKit
import Combine

/// Every user preference, in one place. Values live in `UserDefaults`; the save folder
/// is kept as a security-scoped bookmark so it keeps working inside the App Sandbox.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let annotate = "annotateMode"
        static let collect = "collectSnapshots"
        static let copyPath = "copyPathMode"
        static let welcome = "welcomeCompleted"
        static let shortcutsConfirmed = "shortcutsConfirmed"
        static let shortcuts = "shortcuts"
        static let folderBookmark = "saveFolderBookmark"
        static let legacyFolderPath = "saveLocation"
        static let toolStyles = "toolStyles"
        static let recordMicrophone = "recordMicrophone"
        static let recordSystemAudio = "recordSystemAudio"
        static let recordCamera = "recordCamera"
        static let recordShowsClicks = "recordShowsClicks"
        static let recordCountdown = "recordCountdown"
        static let microphoneID = "microphoneDeviceID"
        static let cameraID = "cameraDeviceID"
        static let videoFormat = "videoExportFormat"
        static let gifFrameRate = "gifFrameRate"
        static let gifMaxWidth = "gifMaxWidth"
    }

    private let defaults: UserDefaults

    /// Open the editor after each capture. Off copies straight to the clipboard.
    @Published var annotateMode: Bool { didSet { defaults.set(annotateMode, forKey: Key.annotate) } }
    /// Keep captures in the Snapshot Collection.
    @Published var collectMode: Bool { didSet { defaults.set(collectMode, forKey: Key.collect) } }
    /// After saving, also copy the file's path.
    @Published var copyPathMode: Bool { didSet { defaults.set(copyPathMode, forKey: Key.copyPath) } }
    /// Set only when the user finishes the welcome window.
    @Published var welcomeCompleted: Bool { didSet { defaults.set(welcomeCompleted, forKey: Key.welcome) } }
    /// True once the user has chosen shortcuts, in the welcome guide or in Settings.
    /// Global shortcuts are registered only after that.
    @Published private(set) var shortcutsConfirmed: Bool
    @Published private(set) var shortcuts: [CaptureAction: Shortcut]
    @Published private(set) var saveFolderURL: URL?
    /// Shortcuts the system refused to register this session. Not stored.
    @Published var unavailableShortcuts: Set<CaptureAction> = []

    // Recording. Microphone and camera are off until the user turns them on, so a first
    // recording never raises a permission prompt the user did not ask for.
    @Published var recordMicrophone: Bool { didSet { defaults.set(recordMicrophone, forKey: Key.recordMicrophone) } }
    @Published var recordSystemAudio: Bool { didSet { defaults.set(recordSystemAudio, forKey: Key.recordSystemAudio) } }
    @Published var recordCamera: Bool { didSet { defaults.set(recordCamera, forKey: Key.recordCamera) } }
    /// Draws a ring where the user clicks, which helps viewers follow a tutorial.
    @Published var recordShowsClicks: Bool { didSet { defaults.set(recordShowsClicks, forKey: Key.recordShowsClicks) } }
    @Published var recordCountdown: Bool { didSet { defaults.set(recordCountdown, forKey: Key.recordCountdown) } }
    /// Capture device unique IDs. Nil means the system default.
    @Published var microphoneID: String? { didSet { defaults.set(microphoneID, forKey: Key.microphoneID) } }
    @Published var cameraID: String? { didSet { defaults.set(cameraID, forKey: Key.cameraID) } }
    /// The video editor's last export choices.
    @Published var videoFormat: VideoFormat { didSet { defaults.set(videoFormat.rawValue, forKey: Key.videoFormat) } }
    @Published var gifFrameRate: Int { didSet { defaults.set(gifFrameRate, forKey: Key.gifFrameRate) } }
    /// Zero keeps the recording's own width.
    @Published var gifMaxWidth: Int { didSet { defaults.set(gifMaxWidth, forKey: Key.gifMaxWidth) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        annotateMode = defaults.object(forKey: Key.annotate) == nil ? true : defaults.bool(forKey: Key.annotate)
        collectMode = defaults.bool(forKey: Key.collect)
        copyPathMode = defaults.bool(forKey: Key.copyPath)
        welcomeCompleted = defaults.bool(forKey: Key.welcome)
        shortcutsConfirmed = defaults.bool(forKey: Key.shortcutsConfirmed) || defaults.bool(forKey: Key.welcome)
        shortcuts = Self.decodeShortcuts(defaults.data(forKey: Key.shortcuts))
        recordMicrophone = defaults.bool(forKey: Key.recordMicrophone)
        recordSystemAudio = defaults.bool(forKey: Key.recordSystemAudio)
        recordCamera = defaults.bool(forKey: Key.recordCamera)
        recordShowsClicks = defaults.object(forKey: Key.recordShowsClicks) == nil ? true : defaults.bool(forKey: Key.recordShowsClicks)
        recordCountdown = defaults.object(forKey: Key.recordCountdown) == nil ? true : defaults.bool(forKey: Key.recordCountdown)
        microphoneID = defaults.string(forKey: Key.microphoneID)
        cameraID = defaults.string(forKey: Key.cameraID)
        videoFormat = VideoFormat(rawValue: defaults.string(forKey: Key.videoFormat) ?? "") ?? .mov
        gifFrameRate = GIFOptions.frameRates.contains(defaults.integer(forKey: Key.gifFrameRate))
            ? defaults.integer(forKey: Key.gifFrameRate) : GIFOptions.defaultFrameRate
        gifMaxWidth = defaults.object(forKey: Key.gifMaxWidth) == nil || !GIFOptions.widths.contains(defaults.integer(forKey: Key.gifMaxWidth))
            ? GIFOptions.defaultWidth : defaults.integer(forKey: Key.gifMaxWidth)
        saveFolderURL = nil
        migrateLegacySaveFolder()
        saveFolderURL = resolveSaveFolder()?.url
    }

    // MARK: Shortcuts

    func shortcut(for action: CaptureAction) -> Shortcut? {
        shortcuts[action]
    }

    /// Assigns a shortcut, taking it away from any other action that had it. Only the
    /// user's own choices come through here, so the call also confirms shortcuts.
    func setShortcut(_ shortcut: Shortcut?, for action: CaptureAction) {
        if !shortcutsConfirmed {
            shortcutsConfirmed = true
            defaults.set(true, forKey: Key.shortcutsConfirmed)
        }
        var updated = shortcuts
        if let shortcut {
            for (other, existing) in updated where other != action && existing == shortcut {
                updated[other] = nil
            }
            updated[action] = shortcut
        } else {
            updated[action] = nil
        }
        shortcuts = updated
        let stored = Dictionary(uniqueKeysWithValues: updated.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: Key.shortcuts)
    }

    private static func decodeShortcuts(_ data: Data?) -> [CaptureAction: Shortcut] {
        guard let data, let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) else { return [:] }
        var result: [CaptureAction: Shortcut] = [:]
        for (name, shortcut) in stored {
            if let action = CaptureAction(rawValue: name) { result[action] = shortcut }
        }
        return result
    }

    // MARK: Tool styles

    func toolStyles() -> [String: AnnotationStyle] {
        guard let data = defaults.data(forKey: Key.toolStyles),
              let styles = try? JSONDecoder().decode([String: AnnotationStyle].self, from: data) else { return [:] }
        return styles
    }

    func setToolStyle(_ style: AnnotationStyle, for tool: String) {
        var styles = toolStyles()
        guard styles[tool] != style else { return }
        styles[tool] = style
        defaults.set(try? JSONEncoder().encode(styles), forKey: Key.toolStyles)
    }

    // MARK: Save folder

    var saveFolderName: String? { saveFolderURL?.lastPathComponent }

    @discardableResult
    func setSaveFolder(_ url: URL) -> Bool {
        guard let bookmark = Self.makeBookmark(for: url) else { return false }
        defaults.set(bookmark, forKey: Key.folderBookmark)
        saveFolderURL = url
        return true
    }

    func clearSaveFolder() {
        defaults.removeObject(forKey: Key.folderBookmark)
        saveFolderURL = nil
    }

    /// Runs `body` with permission to write in the chosen folder. Returns nil when no
    /// folder is set or it can no longer be reached, so the caller can ask with a save panel.
    func withSaveFolder<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let folder = openSaveFolder() else { return nil }
        defer { if folder.scoped { folder.url.stopAccessingSecurityScopedResource() } }
        return try body(folder.url)
    }

    /// The same, for work that waits, such as copying a large file off the main thread.
    /// Permission lasts until `body` finishes.
    func withSaveFolder<T>(_ body: (URL) async throws -> T) async rethrows -> T? {
        guard let folder = openSaveFolder() else { return nil }
        defer { if folder.scoped { folder.url.stopAccessingSecurityScopedResource() } }
        return try await body(folder.url)
    }

    /// Starts access to the chosen folder. The caller stops it when `scoped` is true.
    private func openSaveFolder() -> (url: URL, scoped: Bool)? {
        guard let resolved = resolveSaveFolder() else {
            if saveFolderURL != nil { saveFolderURL = nil }
            return nil
        }
        let scoped = resolved.url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            if scoped { resolved.url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if resolved.stale, let fresh = Self.makeBookmark(for: resolved.url) {
            defaults.set(fresh, forKey: Key.folderBookmark)
        }
        return (resolved.url, scoped)
    }

    private func resolveSaveFolder() -> (url: URL, stale: Bool)? {
        guard let data = defaults.data(forKey: Key.folderBookmark) else { return nil }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        if let url = try? URL(resolvingBookmarkData: data, options: [], bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        return nil
    }

    private static func makeBookmark(for url: URL) -> Data? {
        if let scoped = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return scoped
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Versions before 1.5 stored the folder as a plain path.
    private func migrateLegacySaveFolder() {
        guard let path = defaults.string(forKey: Key.legacyFolderPath) else { return }
        defaults.removeObject(forKey: Key.legacyFolderPath)
        guard defaults.data(forKey: Key.folderBookmark) == nil else { return }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
           let bookmark = Self.makeBookmark(for: URL(fileURLWithPath: path, isDirectory: true)) {
            defaults.set(bookmark, forKey: Key.folderBookmark)
        }
    }

    // MARK: File names

    static func screenshotBaseName(at date: Date = Date()) -> String {
        "Screenshot_\(timestamp(date))"
    }

    static func recordingBaseName(at date: Date = Date()) -> String {
        "Recording_\(timestamp(date))"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    /// A name in `folder` that nothing occupies yet: `base.png`, then `base_2.png`, and so on.
    static func uniqueFileURL(
        in folder: URL,
        base: String,
        fileExtension: String = "png",
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var suffix = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base)_\(suffix)").appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }
}
