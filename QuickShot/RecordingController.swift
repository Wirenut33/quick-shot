//
//  RecordingController.swift
//  QuickShot
//

import AppKit
import ScreenCaptureKit

/// Runs a screen recording from start to finish: choose what to record, show the camera
/// and a countdown, record until stopped, and hand back the movie.
@MainActor
final class RecordingController {
    enum State: Equatable {
        case idle
        /// Asking for permission or waiting for the user to choose an area.
        case preparing
        case countingDown
        case recording(since: Date)
        case finishing
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?() } }
    }
    var onStateChange: (() -> Void)?
    /// The system ended the recording, for example from its screen-sharing indicator.
    var onInterrupted: (() -> Void)?

    private let settings: AppSettings
    private var recorder: ScreenRecorder?
    private var camera: CameraBubble?
    private var frame: RecordingFrame?
    private var overlay: SelectionOverlayController?
    private var cancelRequested = false
    /// macOS ended the stream before `start` finished.
    private var interruptedDuringStart = false

    /// Recordings wait here until the editor exports or discards them.
    static var recordingsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot Recordings", isDirectory: true)
    }

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isIdle: Bool { state == .idle }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var elapsed: TimeInterval {
        if case .recording(let since) = state { return Date().timeIntervalSince(since) }
        return 0
    }

    /// Returns once recording has begun. Throws `ScreenshotError.cancelled` if the user
    /// backs out before then. The state leaves `.idle` at once, before `delay`, so a second
    /// press of the shortcut during the delay cancels instead of starting twice.
    func start(_ action: CaptureAction, after delay: TimeInterval = 0) async throws {
        guard state == .idle else { return }
        state = .preparing
        cancelRequested = false
        interruptedDuringStart = false
        do {
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            try checkCancelled()
            try await begin(action)
        } catch {
            cleanUp()
            if let recorder { await recorder.cancel() }
            recorder = nil
            state = .idle
            throw error
        }
    }

    private func begin(_ action: CaptureAction) async throws {
        if settings.recordMicrophone { try await ScreenRecorder.requestAccess(for: .audio) }
        if settings.recordCamera { try await ScreenRecorder.requestAccess(for: .video) }
        try checkCancelled()

        let content = try await CaptureEngine.shareableContent()
        let display: SCDisplay
        var sourceRect: CGRect?
        if action == .recordSelection {
            (display, sourceRect) = try await chooseRegion(in: content)
        } else {
            guard let underPointer = CaptureEngine.display(underPointerIn: content) else { throw ScreenshotError.noDisplay }
            display = underPointer
        }
        try checkCancelled()

        let screenFrame = NSScreen.screens.first { $0.displayID == display.displayID }?.frame
            ?? CGRect(origin: .zero, size: display.frame.size)
        let region = sourceRect.map { RecordingGeometry.appKitRect(for: $0, screenFrame: screenFrame) } ?? screenFrame
        if sourceRect != nil {
            let outline = RecordingFrame(region: region)
            outline.show()
            frame = outline
        }
        if settings.recordCamera {
            let bubble = try CameraBubble(deviceID: settings.cameraID, frame: RecordingGeometry.cameraBubbleFrame(in: region))
            bubble.show()
            camera = bubble
        }

        if settings.recordCountdown {
            state = .countingDown
            guard await RecordingCountdown.run(over: region) else { throw ScreenshotError.cancelled }
        }
        try checkCancelled()
        // Let the countdown leave the screen before the first frame.
        try? await Task.sleep(nanoseconds: 120_000_000)

        try FileManager.default.createDirectory(at: Self.recordingsFolder, withIntermediateDirectories: true)
        let url = AppSettings.uniqueFileURL(in: Self.recordingsFolder, base: AppSettings.recordingBaseName(), fileExtension: "mov")
        let recorder = ScreenRecorder(outputURL: url)
        recorder.onInterrupted = { [weak self] in self?.recorderInterrupted() }
        self.recorder = recorder
        try await recorder.start(RecordingRequest(
            display: display,
            sourceRect: sourceRect,
            systemAudio: settings.recordSystemAudio,
            microphone: settings.recordMicrophone,
            microphoneID: settings.microphoneID,
            showsClicks: settings.recordShowsClicks
        ))
        try checkCancelled()
        if interruptedDuringStart {
            throw RecordingError.failed("macOS stopped the recording as it started. Try again.")
        }
        state = .recording(since: Date())
    }

    /// An interruption while starting is held until `start` settles, which then fails,
    /// so the menu bar never shows a recording that has already stopped.
    private func recorderInterrupted() {
        if isRecording {
            onInterrupted?()
        } else {
            interruptedDuringStart = true
        }
    }

    /// Freezes the screen so the user can drag an area or pick a window, as for a screenshot.
    private func chooseRegion(in content: SCShareableContent) async throws -> (SCDisplay, CGRect) {
        guard !content.displays.isEmpty else { throw ScreenshotError.noDisplay }
        let displays = try await CaptureEngine.captureAll(content.displays)
        // A cancel while the screen was being frozen must not open the overlay.
        try checkCancelled()
        let controller = SelectionOverlayController(
            displays: displays,
            windows: CaptureEngine.windowCandidates(in: content),
            mode: .area,
            areaHint: "Drag over the area to record",
            returnsRegion: true
        )
        overlay = controller
        defer { overlay = nil }
        guard case .region(let rect, let displayID) = await controller.run(),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotError.cancelled
        }
        guard let snapped = RecordingGeometry.sourceRect(rect, displaySize: display.frame.size) else {
            throw RecordingError.failed("That area is too small to record. Drag over a larger area.")
        }
        return (display, snapped)
    }

    /// Ends the recording and returns the movie file.
    func stop() async throws -> URL {
        guard isRecording, let recorder else { throw ScreenshotError.cancelled }
        state = .finishing
        defer {
            cleanUp()
            self.recorder = nil
            state = .idle
        }
        return try await recorder.stop()
    }

    /// Backs out of a recording that has not started yet.
    func cancel() {
        cancelRequested = true
        overlay?.cancel()
        RecordingCountdown.cancel()
    }

    private func checkCancelled() throws {
        if cancelRequested { throw ScreenshotError.cancelled }
    }

    private func cleanUp() {
        camera?.close()
        camera = nil
        frame?.close()
        frame = nil
    }

    /// Removes recordings and exports left over from earlier sessions.
    static func removeLeftovers(olderThan age: TimeInterval = 24 * 60 * 60) {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-age)
        for folder in [recordingsFolder, recordingsFolder.appendingPathComponent("Exports")] {
            guard let items = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for item in items where item.lastPathComponent != "Exports" {
                let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if modified < cutoff { try? manager.removeItem(at: item) }
            }
        }
    }
}
