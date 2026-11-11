//
//  VideoExporter.swift
//  QuickShot
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// What the editor asks for: the part of the recording to keep and whether its sound stays.
nonisolated struct VideoEdit: Hashable, Sendable {
    /// Seconds from the start of the recording.
    var start: Double
    var end: Double
    var includesAudio: Bool
}

nonisolated enum VideoExportError: LocalizedError {
    case noVideo
    case emptyRange
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return "The recording has no video."
        case .emptyRange: return "Nothing is selected to export. Widen the trim range."
        case .failed(let detail): return detail.isEmpty ? "The recording could not be exported." : detail
        }
    }
}

/// Turns a recording into a movie or an animated GIF. Everything runs on this Mac.
nonisolated enum VideoExporter {
    /// Writes the trimmed recording as a QuickTime movie without re-encoding the video.
    /// Several audio tracks, such as system audio and the microphone, are mixed into one,
    /// because many players and web apps play only the first.
    @concurrent nonisolated static func exportMovie(from source: URL, edit: VideoEdit, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let range = try await timeRange(of: asset, start: edit.start, end: edit.end)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw VideoExportError.noVideo }

        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoExportError.failed("QuickShot could not prepare the movie.")
        }
        // ScreenCaptureKit adds a frame only when the picture changes, so the video track
        // can end long before the sound does (and, in principle, start after it). Those
        // still stretches hold the nearest frame, so every part of the selection has a picture.
        let trackRange = try await sourceVideo.load(.timeRange)
        guard !trackRange.isEmpty else { throw VideoExportError.noVideo }
        let frameLength = CMTimeMinimum(CMTime(value: 1, timescale: 60), trackRange.duration)
        let firstFrame = CMTimeRange(start: trackRange.start, duration: frameLength)
        let lastFrame = CMTimeRange(start: trackRange.end - frameLength, duration: frameLength)
        func hold(_ frame: CMTimeRange, at start: CMTime, for length: CMTime) throws {
            guard length > CMTime(value: 1, timescale: 1_000) else { return }
            try video.insertTimeRange(frame, of: sourceVideo, at: start)
            video.scaleTimeRange(CMTimeRange(start: start, duration: frame.duration), toDuration: length)
        }
        let videoRange = trackRange.intersection(range)
        if videoRange.isEmpty {
            // The whole selection falls in a still stretch before the first frame or after the last.
            try hold(range.end <= trackRange.start ? firstFrame : lastFrame, at: .zero, for: range.duration)
        } else {
            let lead = videoRange.start - range.start
            try hold(firstFrame, at: .zero, for: lead)
            try video.insertTimeRange(videoRange, of: sourceVideo, at: lead)
            let covered = videoRange.end - range.start
            try hold(lastFrame, at: covered, for: range.duration - covered)
        }
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)

        var audioTracks: [AVMutableCompositionTrack] = []
        if edit.includesAudio {
            for sourceAudio in try await asset.loadTracks(withMediaType: .audio) {
                let audioRange = try await sourceAudio.load(.timeRange).intersection(range)
                guard !audioRange.isEmpty,
                      let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try audio.insertTimeRange(audioRange, of: sourceAudio, at: audioRange.start - range.start)
                audioTracks.append(audio)
            }
        }

        // Export sessions keep every audio track as it is, so several are first mixed
        // into one file, which then replaces them. The video is never re-encoded.
        var mixedFile: URL?
        defer { if let mixedFile { try? FileManager.default.removeItem(at: mixedFile) } }
        if audioTracks.count > 1 {
            let mixed = FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-mix-\(UUID().uuidString).m4a")
            mixedFile = mixed
            try await mixAudio(audioTracks, of: composition, to: mixed)
            audioTracks.forEach { composition.removeTrack($0) }
            let mixedAsset = AVURLAsset(url: mixed)
            if let mixedTrack = try await mixedAsset.loadTracks(withMediaType: .audio).first,
               let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let mixedRange = try await mixedTrack.load(.timeRange)
                try audio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(mixedRange.duration, range.duration)),
                                          of: mixedTrack, at: .zero)
            }
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoExportError.failed("This Mac cannot export the movie.")
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try await session.export(to: destination, as: .mov)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VideoExportError.failed(error.localizedDescription)
        }
    }

    /// Mixes audio tracks into a single AAC track, the way a listener hears them together.
    nonisolated private static func mixAudio(_ tracks: [AVAssetTrack], of asset: AVAsset, to url: URL) async throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { throw VideoExportError.failed("QuickShot could not read the recording's sound.") }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw VideoExportError.failed("QuickShot could not mix the recording's sound.") }
        writer.add(input)

        guard reader.startReading(), writer.startWriting() else {
            reader.cancelReading()
            throw VideoExportError.failed((reader.error ?? writer.error)?.localizedDescription ?? "")
        }
        writer.startSession(atSourceTime: .zero)
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw CancellationError()
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard input.append(buffer) else { break }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard reader.status == .completed, writer.status == .completed else {
            throw VideoExportError.failed((reader.error ?? writer.error)?.localizedDescription ?? "The sound could not be mixed.")
        }
    }

    /// Writes the trimmed recording as a looping GIF. Frames that do not change are merged
    /// into one longer frame, which keeps screen recordings small.
    @concurrent nonisolated static func exportGIF(
        from source: URL,
        start: Double,
        end: Double,
        frameRate: Int,
        maxWidth: Int,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let asset = AVURLAsset(url: source)
        let range = try await timeRange(of: asset, start: start, end: end)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoExportError.noVideo }
        // Past the video's last frame the screen was still, so the last frame is what was shown.
        let lastFrameTime = try await track.load(.timeRange).end.seconds - 0.001
        let natural = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
        let size = RecordingGeometry.gifSize(natural: CGSize(width: abs(natural.width), height: abs(natural.height)), maxWidth: maxWidth)
        let times = RecordingGeometry.frameTimes(start: range.start.seconds, duration: range.duration.seconds, frameRate: frameRate)
        guard !times.isEmpty, size.width > 0 else { throw VideoExportError.emptyRange }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        // The frame on screen at each moment; a little leeway before it saves decoding.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5 / Double(frameRate), preferredTimescale: 6_000)
        generator.requestedTimeToleranceAfter = .zero

        try? FileManager.default.removeItem(at: destination)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw VideoExportError.failed("QuickShot could not create the GIF file.")
        }
        CGImageDestinationSetProperties(output, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        // Each frame is held from its own sample time until the next different frame, and
        // the last one until the end of the selection, so the GIF lasts exactly as long.
        let clipStart = range.start.seconds
        let clipLength = range.duration.seconds
        var pending: (image: CGImage, pixels: Data?, offset: Double)?
        func write(_ frame: (image: CGImage, pixels: Data?, offset: Double), until end: Double) {
            let delay = RecordingGeometry.gifDelay(from: frame.offset, to: end)
            CGImageDestinationAddImage(output, frame.image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
        }

        for (index, seconds) in times.enumerated() {
            try Task.checkCancellation()
            let image: CGImage
            do {
                image = try await generator.image(at: CMTime(seconds: min(seconds, lastFrameTime), preferredTimescale: 6_000)).image
            } catch {
                throw VideoExportError.failed(error.localizedDescription)
            }
            let pixels = image.dataProvider?.data as Data?
            let offset = seconds - clipStart
            // An unchanged frame simply extends the one before it.
            let unchanged: Bool
            if let previous = pending?.pixels, let pixels {
                unchanged = looksIdentical(previous, pixels)
            } else {
                unchanged = false
            }
            if !unchanged {
                if let pending { write(pending, until: offset) }
                pending = (image, pixels, offset)
            }
            progress(Double(index + 1) / Double(times.count))
        }
        if let pending { write(pending, until: clipLength) }

        guard CGImageDestinationFinalize(output) else {
            throw VideoExportError.failed("QuickShot could not finish the GIF file.")
        }
    }

    /// Decoding the same picture twice can differ by a few levels per channel, depending
    /// on the decoder and the frame type, so frames count as unchanged when no byte moves
    /// further than `tolerance`. A real change, such as a moving pointer or a typed
    /// character, moves far more. Each frame is compared with the first of its run, so
    /// small drifts cannot add up.
    static func looksIdentical(_ first: Data, _ second: Data, tolerance: UInt8 = 12) -> Bool {
        guard first.count == second.count else { return false }
        return first.withUnsafeBytes { left in
            second.withUnsafeBytes { right in
                let a = left.bindMemory(to: UInt8.self)
                let b = right.bindMemory(to: UInt8.self)
                for index in 0..<a.count {
                    let difference = a[index] > b[index] ? a[index] - b[index] : b[index] - a[index]
                    if difference > tolerance { return false }
                }
                return true
            }
        }
    }

    /// The recording's length in seconds.
    @concurrent nonisolated static func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// The requested span, kept inside the recording.
    nonisolated private static func timeRange(of asset: AVAsset, start: Double, end: Double) async throws -> CMTimeRange {
        let duration = try await asset.load(.duration)
        let lower = CMTime(seconds: max(0, start), preferredTimescale: 6_000)
        let upper = CMTimeMinimum(CMTime(seconds: max(0, end), preferredTimescale: 6_000), duration)
        guard upper > lower, (upper - lower).seconds >= 0.05 else { throw VideoExportError.emptyRange }
        return CMTimeRange(start: lower, end: upper)
    }
}
