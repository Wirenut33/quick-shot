import AVFoundation
import AppKit
import ImageIO

/// Recording geometry, timing, and real MOV and GIF exports from a synthetic recording
/// that has two audio tracks, the way ScreenCaptureKit writes system audio and the microphone.
@main
struct RecordingTests {
    static func main() async throws {
        // MARK: Geometry

        // Even pixel sizes for H.264, at 1× and 2×.
        precondition(RecordingGeometry.pixelSize(points: CGSize(width: 801, height: 451), scale: 1) == (800, 450))
        precondition(RecordingGeometry.pixelSize(points: CGSize(width: 400.5, height: 300.25), scale: 2) == (800, 600))
        precondition(RecordingGeometry.pixelSize(points: CGSize(width: 0.2, height: 0.2), scale: 1) == (2, 2))

        // Selections snap outward to whole points and stay on the display.
        let display = CGSize(width: 1_440, height: 900)
        precondition(RecordingGeometry.sourceRect(CGRect(x: 10.4, y: 20.6, width: 99.2, height: 50.1), displaySize: display)
                     == CGRect(x: 10, y: 20, width: 100, height: 51))
        precondition(RecordingGeometry.sourceRect(CGRect(x: 1_400, y: 850, width: 200, height: 200), displaySize: display)
                     == CGRect(x: 1_400, y: 850, width: 40, height: 50))
        precondition(RecordingGeometry.sourceRect(CGRect(x: 0, y: 0, width: 8, height: 8), displaySize: display) == nil,
                     "A sliver is not worth recording")
        precondition(RecordingGeometry.sourceRect(CGRect(x: 2_000, y: 0, width: 80, height: 80), displaySize: display) == nil)

        // Top-left display rectangles map to AppKit's bottom-left global space, on any display.
        precondition(RecordingGeometry.appKitRect(for: CGRect(x: 100, y: 50, width: 200, height: 100),
                                                  screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900))
                     == CGRect(x: 100, y: 750, width: 200, height: 100))
        precondition(RecordingGeometry.appKitRect(for: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                  screenFrame: CGRect(x: -1_920, y: 900, width: 1_920, height: 1_080))
                     == CGRect(x: -1_920, y: 1_970, width: 10, height: 10))

        // The camera bubble sits inside the bottom-right of the area and shrinks for small areas.
        let region = CGRect(x: 100, y: 100, width: 1_000, height: 600)
        let bubble = RecordingGeometry.cameraBubbleFrame(in: region)
        precondition(bubble == CGRect(x: 896, y: 124, width: 180, height: 180), "\(bubble)")
        let small = RecordingGeometry.cameraBubbleFrame(in: CGRect(x: 0, y: 0, width: 200, height: 160))
        precondition(region.contains(bubble) && CGRect(x: 0, y: 0, width: 200, height: 160).contains(small) && small.width == 64, "\(small)")
        // An area smaller than the minimum bubble still holds the whole bubble.
        let tiny = CGRect(x: 10, y: 10, width: 40, height: 30)
        let tinyBubble = RecordingGeometry.cameraBubbleFrame(in: tiny)
        precondition(tiny.contains(tinyBubble) && tinyBubble.width == 30, "\(tinyBubble)")

        // GIF delays round the frame boundaries, not each delay, so the length stays exact.
        let fifteen = (0..<150).map { RecordingGeometry.gifDelay(from: Double($0) / 15, to: Double($0 + 1) / 15) }
        precondition(abs(fifteen.reduce(0, +) - 10) < 0.001, "150 frames at 15 fps must last 10 s, got \(fifteen.reduce(0, +))")
        precondition(RecordingGeometry.gifDelay(from: 0, to: 0.05) == 0.05)
        precondition(RecordingGeometry.gifDelay(from: 0.5, to: 0.5) == 0.01, "A frame is never held for zero time")

        // GIF frames keep the aspect ratio and are never enlarged.
        precondition(RecordingGeometry.gifSize(natural: CGSize(width: 1_600, height: 900), maxWidth: 800) == CGSize(width: 800, height: 450))
        precondition(RecordingGeometry.gifSize(natural: CGSize(width: 400, height: 300), maxWidth: 800) == CGSize(width: 400, height: 300))
        precondition(RecordingGeometry.gifSize(natural: CGSize(width: 1_600, height: 900), maxWidth: 0) == CGSize(width: 1_600, height: 900))
        precondition(RecordingGeometry.frameTimes(start: 1, duration: 1, frameRate: 4) == [1, 1.25, 1.5, 1.75])
        precondition(RecordingGeometry.frameTimes(start: 0, duration: 0, frameRate: 10).isEmpty)
        precondition(RecordingGeometry.timecode(7.9) == "0:07" && RecordingGeometry.timecode(750) == "12:30"
                     && RecordingGeometry.timecode(3_723) == "1:02:03" && RecordingGeometry.timecode(.nan) == "0:00")

        // Recording actions have their own stable shortcut identifiers.
        precondition(CaptureAction.recordScreen.isRecording && CaptureAction.recordSelection.isRecording && !CaptureAction.selection.isRecording)
        precondition(Set(CaptureAction.allCases.map(\.hotKeyID)).count == CaptureAction.allCases.count)

        // MARK: Export

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuickShot-RecordingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        // Two seconds at 10 fps: a different colour every half second, with two audio tracks.
        try await SyntheticRecording.write(to: source, seconds: 2, frameRate: 10, audioTracks: 2)
        let sourceAsset = AVURLAsset(url: source)
        let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio).count
        precondition(sourceAudio == 2)

        // Trimmed, with sound: one mixed audio track, the right length.
        let trimmed = folder.appendingPathComponent("trimmed.mov")
        try await VideoExporter.exportMovie(from: source, edit: VideoEdit(start: 0.5, end: 1.5, includesAudio: true), to: trimmed)
        let trimmedAsset = AVURLAsset(url: trimmed)
        let trimmedDuration = try await trimmedAsset.load(.duration).seconds
        precondition(abs(trimmedDuration - 1) < 0.15, "Trimmed movie lasts \(trimmedDuration)s")
        let mixed = try await trimmedAsset.loadTracks(withMediaType: .audio).count
        precondition(mixed == 1, "System audio and microphone must be mixed into one track, found \(mixed)")
        let trimmedVideo = try await trimmedAsset.loadTracks(withMediaType: .video).count
        precondition(trimmedVideo == 1)

        // Muted: no audio at all, video copied untouched.
        let muted = folder.appendingPathComponent("muted.mov")
        try await VideoExporter.exportMovie(from: source, edit: VideoEdit(start: 0, end: 10, includesAudio: false), to: muted)
        let mutedAsset = AVURLAsset(url: muted)
        let mutedAudio = try await mutedAsset.loadTracks(withMediaType: .audio)
        precondition(mutedAudio.isEmpty)
        let mutedDuration = try await mutedAsset.load(.duration).seconds
        precondition(abs(mutedDuration - 2) < 0.15, "An end past the recording is clamped, got \(mutedDuration)s")

        // An empty range is refused rather than producing a broken file.
        do {
            try await VideoExporter.exportMovie(from: source, edit: VideoEdit(start: 1, end: 1, includesAudio: true), to: folder.appendingPathComponent("empty.mov"))
            preconditionFailure("An empty range must be refused")
        } catch VideoExportError.emptyRange {}

        // Decoder noise is tolerated; a real change is not.
        let still = Data(repeating: 120, count: 4_096)
        var noisy = still
        noisy[10] = 128
        noisy[2_000] = 113
        precondition(VideoExporter.looksIdentical(still, noisy), "Decoder noise must not count as a change")
        var changed = still
        changed[3_000] = 200
        precondition(!VideoExporter.looksIdentical(still, changed), "A visible change must be kept")
        precondition(!VideoExporter.looksIdentical(still, Data(repeating: 120, count: 4_000)))

        // GIF: 1 s at 10 fps from a clip whose colour changes every 0.5 s. Unchanged
        // frames merge, so two frames of 0.5 s each remain, scaled to the requested width.
        let gif = folder.appendingPathComponent("clip.gif")
        let progress = ProgressBox()
        try await VideoExporter.exportGIF(from: source, start: 0, end: 1, frameRate: 10, maxWidth: 160, to: gif) { progress.value = $0 }
        precondition(progress.value == 1)
        guard let gifSource = CGImageSourceCreateWithURL(gif as CFURL, nil) else { preconditionFailure("No GIF written") }
        let frames = CGImageSourceGetCount(gifSource)
        precondition(frames == 2, "Expected identical frames to merge into 2, got \(frames)")
        let properties = CGImageSourceCopyProperties(gifSource, nil) as? [CFString: Any]
        let loop = (properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
        precondition(loop == 0, "The GIF must loop forever")
        var total = 0.0
        for index in 0..<frames {
            let frame = CGImageSourceCopyPropertiesAtIndex(gifSource, index, nil) as? [CFString: Any]
            let gifInfo = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += (gifInfo?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
            precondition((frame?[kCGImagePropertyPixelWidth] as? Int) == 160, "GIF frame width")
            precondition((frame?[kCGImagePropertyPixelHeight] as? Int) == 90, "GIF frame height")
        }
        precondition(abs(total - 1) < 0.05, "GIF frame delays add up to \(total)s")

        // ScreenCaptureKit stops adding frames while the screen is still, so the video can
        // end long before the sound. Every exported part must still have a picture.
        let stillSource = folder.appendingPathComponent("still.mov")
        // Seven frames: red until 0.5 s, then green, so the first and last pictures differ.
        try await SyntheticRecording.write(to: stillSource, seconds: 2, frameRate: 10, audioTracks: 1, videoFrames: 7)
        let stillVideo = try await AVURLAsset(url: stillSource).loadTracks(withMediaType: .video).first!.load(.timeRange).end.seconds
        precondition(stillVideo < 0.8, "The fixture's video must stop early, ends at \(stillVideo)s")
        for (label, edit) in [("after the last frame", VideoEdit(start: 1, end: 1.8, includesAudio: true)),
                              ("across the last frame, muted", VideoEdit(start: 0.1, end: 1.5, includesAudio: false))] {
            let output = folder.appendingPathComponent("still-\(UUID().uuidString).mov")
            try await VideoExporter.exportMovie(from: stillSource, edit: edit, to: output)
            let exported = AVURLAsset(url: output)
            let length = try await exported.load(.duration).seconds
            let videoLength = try await exported.loadTracks(withMediaType: .video).first!.load(.timeRange).duration.seconds
            let expected = edit.end - edit.start
            precondition(abs(length - expected) < 0.1 && abs(videoLength - expected) < 0.1,
                         "\(label): movie \(length)s, video \(videoLength)s, expected \(expected)s")
            // The held picture really is there: near the end, the fixture's last frame (green), not its first (red).
            let generator = AVAssetImageGenerator(asset: exported)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let requested = CMTime(seconds: expected - 0.1, preferredTimescale: 600)
            // A held frame reports the time it starts showing, so only the picture is checked.
            let frame = try await generator.image(at: requested).image
            let pixel = centrePixel(frame)
            precondition(pixel.green > 130 && pixel.red < 90 && pixel.blue < 110, "\(label): held frame is not the last picture: \(pixel)")
        }
        let stillGIF = folder.appendingPathComponent("still.gif")
        try await VideoExporter.exportGIF(from: stillSource, start: 1, end: 1.5, frameRate: 10, maxWidth: 160, to: stillGIF)
        precondition(CGImageSourceCreateWithURL(stillGIF as CFURL, nil).map(CGImageSourceGetCount) ?? 0 >= 1)

        // A selection shorter than one frame interval lasts as long as the selection.
        let short = folder.appendingPathComponent("short.gif")
        try await VideoExporter.exportGIF(from: source, start: 0, end: 0.05, frameRate: 10, maxWidth: 160, to: short)
        guard let shortSource = CGImageSourceCreateWithURL(short as CFURL, nil) else { preconditionFailure("No short GIF") }
        let shortFrame = CGImageSourceCopyPropertiesAtIndex(shortSource, 0, nil) as? [CFString: Any]
        let shortDelay = ((shortFrame?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
        precondition(CGImageSourceGetCount(shortSource) == 1 && abs(shortDelay - 0.05) < 0.001, "Short GIF lasts \(shortDelay)s")

        print("PASS: recording geometry and timecodes, trimmed MOV with mixed audio, muted MOV, empty range refused, deduplicated looping GIF, still stretches keep their picture")
    }
}

/// The colour at the middle of an image, as 8-bit RGB.
func centrePixel(_ image: CGImage) -> (red: Int, green: Int, blue: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let x = CGFloat(image.width / 2), y = CGFloat(image.height / 2)
    context.draw(image, in: CGRect(x: -x, y: -y, width: CGFloat(image.width), height: CGFloat(image.height)))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
}

final class ProgressBox: @unchecked Sendable {
    var value = 0.0
}

/// Writes a small H.264 movie with solid-colour frames and sine-wave audio tracks.
enum SyntheticRecording {
    /// `videoFrames` shorter than the sound mimics ScreenCaptureKit, which stops adding
    /// frames while the screen is still.
    static func write(to url: URL, seconds: Int, frameRate: Int, audioTracks: Int, videoFrames: Int? = nil) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = 320, height = 180
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        video.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(video)

        let sampleRate = 44_100.0
        var audioInputs: [AVAssetWriterInput] = []
        for _ in 0..<audioTracks {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1
            ])
            audio.expectsMediaDataInRealTime = true
            writer.add(audio)
            audioInputs.append(audio)
        }

        guard writer.startWriting() else { throw writer.error ?? VideoExportError.failed("writer") }
        writer.startSession(atSourceTime: .zero)

        let colours: [(UInt8, UInt8, UInt8)] = [(220, 40, 40), (40, 180, 60), (40, 80, 220), (230, 200, 30)]
        let totalSamples = Int(sampleRate) * seconds
        var audioWritten = 0
        func writeAudio(upTo audioTarget: Int) async throws {
            if audioTarget > audioWritten {
                for (track, audio) in audioInputs.enumerated() {
                    let frequency = 440.0 * Double(track + 1)
                    var samples = [Int16](repeating: 0, count: audioTarget - audioWritten)
                    for offset in samples.indices {
                        samples[offset] = Int16(8_000 * sin(2 * .pi * frequency * Double(audioWritten + offset) / sampleRate))
                    }
                    try await waitUntilReady(audio)
                    audio.append(try pcmBuffer(samples, at: audioWritten, sampleRate: sampleRate))
                }
                audioWritten = audioTarget
            }
        }
        // The writer interleaves tracks, so audio and video advance together.
        let frames = min(videoFrames ?? seconds * frameRate, seconds * frameRate)
        for index in 0..<(seconds * frameRate) {
            if index == frames { video.markAsFinished() }
            guard index < frames else {
                try await writeAudio(upTo: min(totalSamples, Int(sampleRate) * (index + 1) / frameRate))
                continue
            }
            try await waitUntilReady(video)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw VideoExportError.failed("pixel buffer") }
            // A new colour every half second.
            let colour = colours[(index * 2 / frameRate) % colours.count]
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                for x in 0..<width {
                    let pixel = base + y * stride + x * 4
                    pixel[0] = colour.2; pixel[1] = colour.1; pixel[2] = colour.0; pixel[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate)))

            try await writeAudio(upTo: min(totalSamples, Int(sampleRate) * (index + 1) / frameRate))
        }
        if frames == seconds * frameRate { video.markAsFinished() }
        audioInputs.forEach { $0.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? VideoExportError.failed("writer") }
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        for _ in 0..<2_500 where !input.isReadyForMoreMediaData {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard input.isReadyForMoreMediaData else { throw VideoExportError.failed("The synthetic writer stalled on \(input.mediaType.rawValue)") }
    }

    private static func pcmBuffer(_ samples: [Int16], at offset: Int, sampleRate: Double) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let length = samples.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block)
        guard let block, let format else { throw VideoExportError.failed("audio buffer") }
        samples.withUnsafeBytes { bytes in
            _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: samples.count,
            presentationTimeStamp: CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        guard let sample else { throw VideoExportError.failed("audio sample") }
        return sample
    }
}
