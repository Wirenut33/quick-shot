//
//  CaptureEngine.swift
//  QuickShot
//

import AppKit
import ScreenCaptureKit

/// One display's frozen frame and where that display sits in global display space.
struct DisplayCapture {
    let displayID: CGDirectDisplayID
    /// Points, origin at the top-left of the primary display.
    let frame: CGRect
    let image: CGImage
}

/// A window the user can pick, with its frame in global display space.
struct WindowCandidate {
    let window: SCWindow
    let frame: CGRect
}

/// Thin wrapper over ScreenCaptureKit. Every capture in the app goes through here,
/// so the direct and App Store builds share one code path.
enum CaptureEngine {
    static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw classify(error)
        }
    }

    static func display(underPointerIn content: SCShareableContent) -> SCDisplay? {
        let pointer = CGEvent(source: nil)?.location ?? .zero
        return content.displays.first { $0.frame.contains(pointer) } ?? content.displays.first
    }

    static func capture(_ display: SCDisplay) async throws -> DisplayCapture {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        // The defaults add the pointer and pick a size unrelated to the display.
        let size = pixelSize(of: display, filter: filter)
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return DisplayCapture(displayID: display.displayID, frame: display.frame, image: image)
        } catch {
            throw classify(error)
        }
    }

    static func captureAll(_ displays: [SCDisplay]) async throws -> [DisplayCapture] {
        var captures: [DisplayCapture] = []
        for display in displays {
            captures.append(try await capture(display))
        }
        return captures
    }

    /// Captures one window on its own, including any part hidden behind other windows.
    static func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(1, CGFloat(filter.pointPixelScale))
        let rect = filter.contentRect.isEmpty ? window.frame : filter.contentRect
        configuration.width = max(1, Int((rect.width * scale).rounded()))
        configuration.height = max(1, Int((rect.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            throw classify(error)
        }
    }

    /// Ordinary application windows, front to back, without QuickShot's own.
    static func windowCandidates(in content: SCShareableContent) -> [WindowCandidate] {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let order = frontToBackOrder()
        return content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0
                    && window.frame.width >= 40 && window.frame.height >= 40
                    && window.owningApplication != nil
                    && window.owningApplication?.processID != ownProcess
            }
            .enumerated()
            .sorted { left, right in
                let leftRank = order[left.element.windowID] ?? Int.max
                let rightRank = order[right.element.windowID] ?? Int.max
                // Windows Quartz does not list keep ScreenCaptureKit's own order.
                return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
            }
            .map { WindowCandidate(window: $0.element, frame: $0.element.frame) }
    }

    static func pixelSize(of display: SCDisplay, filter: SCContentFilter) -> CGSize {
        if let mode = CGDisplayCopyDisplayMode(display.displayID), mode.pixelWidth > 0, mode.pixelHeight > 0 {
            return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        let scale = max(1, CGFloat(filter.pointPixelScale))
        return CGSize(width: (CGFloat(display.width) * scale).rounded(), height: (CGFloat(display.height) * scale).rounded())
    }

    /// Quartz reports stacking order; it supplies no pixels and needs no extra permission.
    private static func frontToBackOrder() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (index, entry) in list.enumerated() {
            if let number = entry[kCGWindowNumber as String] as? Int, order[CGWindowID(number)] == nil {
                order[CGWindowID(number)] = index
            }
        }
        return order
    }

    private static func classify(_ error: Error) -> Error {
        if error is ScreenshotError { return error }
        let nsError = error as NSError
        let declined = nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue
        if declined || !CGPreflightScreenCaptureAccess() {
            return ScreenshotError.permissionRequired
        }
        return ScreenshotError.captureFailed(error.localizedDescription)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
