//
//  CaptureGeometry.swift
//  QuickShot
//

import CoreGraphics
import Foundation

/// The one place that converts between the three coordinate spaces a capture touches:
///
/// - global display space: points, origin at the top-left of the primary display
///   (ScreenCaptureKit and Quartz window frames);
/// - overlay space: points, origin at the top-left of one display's overlay;
/// - image space: pixels, origin at the top-left of that display's frozen frame.
///
/// Each display is converted on its own, so a Retina display beside a 1× display works.
enum CaptureGeometry {
    /// The rectangle spanned by a drag, kept inside the overlay.
    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
            .intersection(bounds)
    }

    /// Converts an overlay rectangle into whole pixels of the frozen frame.
    /// Edges snap outward so a selection never loses the pixel it visibly covers.
    static func pixelRect(for rect: CGRect, overlaySize: CGSize, imageSize: CGSize) -> CGRect {
        guard overlaySize.width > 0, overlaySize.height > 0, !rect.isNull, !rect.isEmpty else { return .zero }
        let scaleX = imageSize.width / overlaySize.width
        let scaleY = imageSize.height / overlaySize.height
        let minX = (rect.minX * scaleX).rounded(.down)
        let minY = (rect.minY * scaleY).rounded(.down)
        let maxX = (rect.maxX * scaleX).rounded(.up)
        let maxY = (rect.maxY * scaleY).rounded(.up)
        let pixels = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(CGRect(origin: .zero, size: imageSize))
        return pixels.isNull ? .zero : pixels
    }

    /// Moves a global rectangle into one display's overlay space.
    static func overlayRect(for globalRect: CGRect, displayFrame: CGRect) -> CGRect {
        globalRect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    /// Index of the frontmost frame under the point. `frames` is ordered front to back.
    static func frontmostIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Pixel dimensions shown beside a selection.
    static func sizeLabel(for pixels: CGRect) -> String {
        "\(Int(pixels.width)) × \(Int(pixels.height))"
    }
}
