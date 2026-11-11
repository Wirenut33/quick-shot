//
//  RecordingModel.swift
//  QuickShot
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The file a recording is exported as.
nonisolated enum VideoFormat: String, CaseIterable, Identifiable {
    case mov, gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mov: return "Movie (MOV)"
        case .gif: return "Animated GIF"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .mov: return .quickTimeMovie
        case .gif: return .gif
        }
    }
}

/// The choices the editor offers for GIF export. GIFs grow quickly, so the defaults
/// favour a file that is easy to paste into a chat or a ticket.
nonisolated enum GIFOptions {
    static let frameRates = [5, 10, 15, 20, 25]
    static let defaultFrameRate = 10
    /// Zero keeps the recording's own width.
    static let widths = [480, 640, 800, 960, 1280, 0]
    static let defaultWidth = 800

    static func widthTitle(_ width: Int) -> String {
        width == 0 ? "Full size" : "\(width) px wide"
    }
}

/// Pure layout and timing rules for recording and export, kept apart so they can be tested.
nonisolated enum RecordingGeometry {
    /// H.264 needs even dimensions. Never smaller than 2×2.
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int {
            let pixels = Int((value * max(scale, 1)).rounded())
            return max(2, pixels - pixels % 2)
        }
        return (even(points.width), even(points.height))
    }

    /// A selection in display points, snapped to whole points and kept on the display.
    /// Returns nil when too little is left to record.
    static func sourceRect(_ rect: CGRect, displaySize: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: displaySize)
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull else { return nil }
        let snapped = CGRect(
            x: clipped.minX.rounded(.down),
            y: clipped.minY.rounded(.down),
            width: clipped.maxX.rounded(.up) - clipped.minX.rounded(.down),
            height: clipped.maxY.rounded(.up) - clipped.minY.rounded(.down)
        ).intersection(bounds)
        return snapped.width >= 16 && snapped.height >= 16 ? snapped : nil
    }

    /// Converts a rectangle measured from a display's top-left corner (ScreenCaptureKit)
    /// into AppKit's global coordinates, whose origin is the primary display's bottom-left.
    static func appKitRect(for rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + rect.minX,
               y: screenFrame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    /// The camera bubble starts in the bottom-right corner of the recorded area, inset so
    /// it does not touch the edge, and shrinks to fit a small area. It is never larger than
    /// the area, so it is always fully recorded.
    static func cameraBubbleFrame(in region: CGRect, preferredDiameter: CGFloat = 180, inset: CGFloat = 24) -> CGRect {
        let fit = min(region.width, region.height)
        let diameter = min(fit, max(60, min(preferredDiameter, fit * 0.4)))
        let margin = min(inset, max(0, (min(region.width, region.height) - diameter) / 2))
        return CGRect(x: region.maxX - diameter - margin, y: region.minY + margin, width: diameter, height: diameter)
    }

    /// The size of each GIF frame: the recording's aspect ratio, no wider than `maxWidth`,
    /// and never enlarged.
    static func gifSize(natural: CGSize, maxWidth: Int) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return .zero }
        guard maxWidth > 0, natural.width > CGFloat(maxWidth) else {
            return CGSize(width: natural.width.rounded(), height: natural.height.rounded())
        }
        let scale = CGFloat(maxWidth) / natural.width
        return CGSize(width: CGFloat(maxWidth), height: max(1, (natural.height * scale).rounded()))
    }

    /// Evenly spaced sample times, in seconds, covering `start ..< start + duration`.
    static func frameTimes(start: Double, duration: Double, frameRate: Int) -> [Double] {
        guard duration > 0, frameRate > 0 else { return [] }
        let count = max(1, Int((duration * Double(frameRate)).rounded(.down)))
        return (0..<count).map { start + Double($0) / Double(frameRate) }
    }

    /// How long a GIF frame shown from `start` to `end` (seconds into the clip) is held.
    /// GIF delays are whole hundredths of a second, so the boundaries are rounded rather
    /// than each delay: rounding every 1/15 s frame to 0.07 s would make a 10 s clip
    /// play for 10.5 s.
    static func gifDelay(from start: Double, to end: Double) -> Double {
        let hundredths = Int((end * 100).rounded()) - Int((start * 100).rounded())
        return Double(max(1, hundredths)) / 100
    }

    /// "0:07", "12:30", "1:02:03".
    static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
