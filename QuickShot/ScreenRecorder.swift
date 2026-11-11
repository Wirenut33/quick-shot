//
//  ScreenRecorder.swift
//  QuickShot
//

import AVFoundation
import ScreenCaptureKit

/// What to record and with which sound.
struct RecordingRequest {
    let display: SCDisplay
    /// Display points measured from the display's top-left corner. Nil records the whole display.
    let sourceRect: CGRect?
    let systemAudio: Bool
    let microphone: Bool
    /// Nil uses the system's default microphone.
    let microphoneID: String?
    let showsClicks: Bool
}

enum RecordingError: LocalizedError {
    case microphoneDenied
    case cameraDenied
    case cameraUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "QuickShot is not allowed to use the microphone. Allow it in System Settings › Privacy & Security › Microphone, or turn Microphone off in the QuickShot menu."
        case .cameraDenied:
            return "QuickShot is not allowed to use the camera. Allow it in System Settings › Privacy & Security › Camera, or turn Camera off in the QuickShot menu."
        case .cameraUnavailable:
            return "No camera is available. Connect one, or turn Camera off in the QuickShot menu."
        case .failed(let detail):
            return detail.isEmpty ? "The recording could not be made." : detail
        }
    }
}

/// Records one display, or part of it, straight to a QuickTime movie with
/// ScreenCaptureKit. The same code runs in the direct and App Store builds.
@MainActor
final class ScreenRecorder {
    let outputURL: URL
    /// Called once if the system ends the recording on its own, for example when the
    /// user chooses Stop in the menu bar's screen-sharing indicator.
    var onInterrupted: (() -> Void)?

    private var stream: SCStream?
    private var events: RecordingEvents?
    private var finished = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var failure: Error?
    private let sampleQueue = DispatchQueue(label: "QuickShot.recording.samples")

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func start(_ request: RecordingRequest) async throws {
        let filter = SCContentFilter(display: request.display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let area = request.sourceRect ?? CGRect(origin: .zero, size: request.display.frame.size)
        if let sourceRect = request.sourceRect { configuration.sourceRect = sourceRect }
        let pixels = RecordingGeometry.pixelSize(points: area.size, scale: CGFloat(filter.pointPixelScale))
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 8
        configuration.showsCursor = true
        configuration.showMouseClicks = request.showsClicks
        configuration.capturesAudio = request.systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = request.microphone
        if request.microphone { configuration.microphoneCaptureDeviceID = request.microphoneID }

        let events = RecordingEvents()
        events.owner = self
        self.events = events

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = outputURL
        recording.outputFileType = .mov
        recording.videoCodecType = .h264
        if #available(macOS 27.0, *), request.systemAudio, request.microphone {
            recording.mixesAudioWithMicrophone = true
        }
        let output = SCRecordingOutput(configuration: recording, delegate: events)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: events)
        do {
            // Sample handlers keep each kind of media flowing; the recording output writes the file.
            try stream.addStreamOutput(events, type: .screen, sampleHandlerQueue: sampleQueue)
            if request.systemAudio { try stream.addStreamOutput(events, type: .audio, sampleHandlerQueue: sampleQueue) }
            if request.microphone { try stream.addStreamOutput(events, type: .microphone, sampleHandlerQueue: sampleQueue) }
            try stream.addRecordingOutput(output)
            self.stream = stream
            try await stream.startCapture()
        } catch {
            self.stream = nil
            throw Self.classify(error)
        }
    }

    /// Ends the recording and returns once the movie file is complete.
    func stop() async throws -> URL {
        if let stream, !finished {
            try? await stream.stopCapture()
        }
        stream = nil
        await waitForFinish(timeout: 5)
        if let failure { throw Self.classify(failure) }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RecordingError.failed("The recording ended before anything was captured.")
        }
        return outputURL
    }

    /// Stops without keeping anything.
    func cancel() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil
        await waitForFinish(timeout: 2)
        try? FileManager.default.removeItem(at: outputURL)
    }

    fileprivate func recordingFinished(_ error: Error?) {
        if let error, failure == nil { failure = error }
        finished = true
        let waiters = finishWaiters
        finishWaiters = []
        waiters.forEach { $0.resume() }
    }

    fileprivate func streamStoppedUnexpectedly() {
        guard stream != nil else { return }
        onInterrupted?()
        onInterrupted = nil
    }

    private func waitForFinish(timeout seconds: Double) async {
        guard !finished else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                // The file may already be complete even if the callback never comes.
                self?.recordingFinished(nil)
            }
        }
    }

    private static func classify(_ error: Error) -> Error {
        if error is RecordingError || error is ScreenshotError { return error }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return ScreenshotError.permissionRequired
        }
        if !CGPreflightScreenCaptureAccess() { return ScreenshotError.permissionRequired }
        return RecordingError.failed(error.localizedDescription)
    }

    // MARK: Permissions

    /// Asks for microphone or camera access when it has never been asked. Throws when
    /// the user has turned it down, so the recording does not start silently without it.
    static func requestAccess(for mediaType: AVMediaType) async throws {
        let denied: RecordingError = mediaType == .audio ? .microphoneDenied : .cameraDenied
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: mediaType) { return }
            throw denied
        default:
            throw denied
        }
    }
}

/// Receives ScreenCaptureKit callbacks on its own queues and hands them to the main actor.
private final class RecordingEvents: NSObject, SCStreamDelegate, SCStreamOutput, SCRecordingOutputDelegate, @unchecked Sendable {
    @MainActor weak var owner: ScreenRecorder?

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.owner?.streamStoppedUnexpectedly() }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.owner?.recordingFinished(error) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.owner?.recordingFinished(nil) }
    }
}
