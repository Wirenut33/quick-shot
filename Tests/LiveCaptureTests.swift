import AppKit
import ScreenCaptureKit

/// Exercises the real capture path: ScreenCaptureKit, the selection overlay and text
/// recognition. It needs Screen Recording permission for the app that runs it (the
/// terminal), so it is run by hand with scripts/live_capture_check.sh and not in CI.
/// Captured pixels stay in memory; nothing from the screen is written to disk.
@main
struct LiveCaptureTests {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard CGPreflightScreenCaptureAccess() else {
            print("SKIP: grant Screen Recording to the terminal running this check")
            return
        }

        // Every display is captured at its true pixel size, without relying on defaults.
        let content = try await CaptureEngine.shareableContent()
        let captures = try await CaptureEngine.captureAll(content.displays)
        precondition(!captures.isEmpty, "No displays captured")
        for capture in captures {
            let mode = CGDisplayCopyDisplayMode(capture.displayID)!
            precondition(capture.image.width == mode.pixelWidth && capture.image.height == mode.pixelHeight,
                         "Display \(capture.displayID) captured \(capture.image.width)x\(capture.image.height), expected \(mode.pixelWidth)x\(mode.pixelHeight)")
            precondition(NSScreen.screens.contains { $0.displayID == capture.displayID }, "Captured display has no matching screen")
        }
        print("ok: \(captures.count) display(s) at native pixel size: " + captures.map { "\($0.image.width)x\($0.image.height)" }.joined(separator: ", "))

        // A single window is captured on its own at the display's scale.
        let candidates = CaptureEngine.windowCandidates(in: content)
        print("ok: \(candidates.count) window candidate(s)")
        if let candidate = candidates.first {
            let image = try await CaptureEngine.capture(candidate.window)
            let scale = CGFloat(image.width) / candidate.frame.width
            precondition(image.width > 0 && image.height > 0 && scale >= 0.99 && scale <= 3.01,
                         "Window capture \(image.width)x\(image.height) for frame \(candidate.frame)")
            precondition(abs(CGFloat(image.height) / candidate.frame.height - scale) < 0.05, "Window capture is distorted")
            print("ok: window captured at \(image.width)x\(image.height), scale \(String(format: "%.2f", scale))")
        }

        let manager = ScreenshotManager()

        // Full screen: the display under the pointer.
        guard case .image(let full) = try await manager.capture(.fullScreen) else { preconditionFailure("Expected an image") }
        precondition(captures.contains { CGFloat($0.image.width) == full.size.width && CGFloat($0.image.height) == full.size.height })
        print("ok: full screen \(Int(full.size.width))x\(Int(full.size.height))")

        // Drives the overlay the way a user would, with synthesized mouse and key events.
        func overlayView(_ manager: ScreenshotManager) async -> OverlayView {
            for _ in 0..<200 {
                if let view = manager.overlay?.overlayViews.first(where: { $0.window?.isVisible == true }) { return view }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            preconditionFailure("The overlay never appeared")
        }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, in view: OverlayView) -> NSEvent {
            let inWindow = view.convert(point, to: nil)
            return NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: 0,
                                      windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ code: UInt16, in view: OverlayView) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        // Area: a 200 x 150 point drag becomes that many points times the display's scale.
        var task = Task { @MainActor in try await manager.capture(.selection) }
        var view = await overlayView(manager)
        precondition(view.window?.level.rawValue == Int(CGShieldingWindowLevel()) && view.bounds.size == view.window?.screen?.frame.size)
        let scale = CGFloat(view.capture.image.width) / view.bounds.width
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 120), in: view))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 101, y: 121), in: view))
        precondition(manager.overlay != nil, "A click without a drag must not end the selection")
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 120), in: view))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 220, y: 200), in: view))
        view.display()
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 270), in: view))
        guard case .image(let area) = try await task.value else { preconditionFailure("Expected an image") }
        precondition(area.size == NSSize(width: 200 * scale, height: 150 * scale), "Area \(area.size) at scale \(scale)")
        precondition(manager.overlay == nil, "The overlay must be gone after a selection")
        print("ok: area selection 200x150 pt gave \(Int(area.size.width))x\(Int(area.size.height)) px at \(scale)x")

        // Escape cancels.
        task = Task { @MainActor in try await manager.capture(.selection) }
        view = await overlayView(manager)
        view.keyDown(with: key(53, in: view))
        do {
            _ = try await task.value
            preconditionFailure("Escape must cancel")
        } catch ScreenshotError.cancelled {
            print("ok: Escape cancels")
        }

        // Space switches to window picking; clicking a window captures that window.
        if let target = candidates.first(where: { candidate in
            captures.contains { $0.displayID == view.capture.displayID && $0.frame.contains(CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)) }
        }) {
            task = Task { @MainActor in try await manager.capture(.selection) }
            view = await overlayView(manager)
            view.keyDown(with: key(49, in: view))
            precondition(manager.overlay?.mode == .window, "Space must switch to window picking")
            let local = CaptureGeometry.overlayRect(for: target.frame, displayFrame: view.capture.frame)
            let point = CGPoint(x: local.midX, y: local.midY)
            view.mouseMoved(with: mouse(.mouseMoved, point, in: view))
            view.display()
            view.mouseDown(with: mouse(.leftMouseDown, point, in: view))
            guard case .image(let picked) = try await task.value else { preconditionFailure("Expected an image") }
            precondition(picked.size.width > 0 && picked.size.height > 0)
            print("ok: window pick gave \(Int(picked.size.width))x\(Int(picked.size.height)) px")
        } else {
            print("skip: no window on the pointer's display to pick")
        }

        // Capture Text returns whatever text is in the area, or an empty string.
        task = Task { @MainActor in try await manager.capture(.text) }
        view = await overlayView(manager)
        precondition(manager.overlay?.allowsWindowMode == false, "Text capture has no window mode")
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 0, y: 0), in: view))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: min(900, view.bounds.width), y: min(500, view.bounds.height)), in: view))
        guard case .text(let text) = try await task.value else { preconditionFailure("Expected text") }
        print("ok: text capture returned \(text.count) character(s)")

        // Global shortcuts: the system accepts a registration and refuses a duplicate.
        let rare = Shortcut(keyCode: 111, modifiers: [.control, .option, .shift, .command]) // ⌃⌥⇧⌘F12
        precondition(HotKeyCenter.shared.register(id: 9_001, shortcut: rare) {}, "The system refused a free shortcut")
        precondition(!HotKeyCenter.shared.register(id: 9_002, shortcut: rare) {}, "A shortcut already held must be reported as unavailable")
        HotKeyCenter.shared.unregisterAll()
        precondition(HotKeyCenter.shared.register(id: 9_002, shortcut: rare) {}, "An unregistered shortcut must be free again")
        HotKeyCenter.shared.unregisterAll()
        let reserved = HotKeyCenter.systemReservedShortcuts()
        print("ok: shortcut registration and conflict detection; macOS reserves \(reserved.count) shortcut(s) here")

        print("PASS: live ScreenCaptureKit capture, overlay area and window selection, cancel, text capture, shortcut registration")
    }
}
