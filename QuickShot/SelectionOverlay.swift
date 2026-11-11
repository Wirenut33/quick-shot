//
//  SelectionOverlay.swift
//  QuickShot
//

import AppKit

/// Shows each display's frozen frame and lets the user drag an area or click a window.
/// Because the frame is frozen, open menus and hover states stay capturable.
@MainActor
final class SelectionOverlayController {
    enum Mode { case area, window }

    enum Outcome {
        case area(CGImage)
        /// The picked window, plus the same region cut from the frozen frame in case a
        /// live capture of the window fails.
        case window(WindowCandidate, fallback: CGImage?)
        /// For recording: the chosen area in display points from the display's top-left
        /// corner. A picked window gives its visible frame on that display.
        case region(CGRect, displayID: CGDirectDisplayID)
        case cancelled
    }

    private let displays: [DisplayCapture]
    private let windows: [WindowCandidate]
    private(set) var mode: Mode
    let areaHint: String
    /// Return the selected rectangle instead of cutting it from the frozen frame.
    let returnsRegion: Bool
    private var panels: [OverlayPanel] = []
    private var continuation: CheckedContinuation<Outcome, Never>?

    var allowsWindowMode: Bool { !windows.isEmpty }
    /// One per display while the overlay is up.
    var overlayViews: [OverlayView] { panels.map(\.overlayView) }

    init(displays: [DisplayCapture], windows: [WindowCandidate], mode: Mode, areaHint: String, returnsRegion: Bool = false) {
        self.displays = displays
        self.windows = windows
        self.mode = windows.isEmpty ? .area : mode
        self.areaHint = areaHint
        self.returnsRegion = returnsRegion
    }

    func run() async -> Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            show()
        }
    }

    private func show() {
        let pointer = NSEvent.mouseLocation
        var keyPanel: OverlayPanel?
        for capture in displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == capture.displayID }) else { continue }
            let frames = windows.map { CaptureGeometry.overlayRect(for: $0.frame, displayFrame: capture.frame) }
            let panel = OverlayPanel(screen: screen, capture: capture, windowFrames: frames, controller: self)
            panels.append(panel)
            if screen.frame.contains(pointer) { keyPanel = panel }
        }
        guard !panels.isEmpty else {
            finish(.cancelled)
            return
        }
        panels.forEach { $0.orderFrontRegardless() }
        let key = keyPanel ?? panels[0]
        key.makeKey()
        key.makeFirstResponder(key.overlayView)
    }

    func toggleMode() {
        guard allowsWindowMode else { return }
        mode = mode == .area ? .window : .area
        panels.forEach { $0.overlayView.modeChanged() }
    }

    func cancel() {
        finish(.cancelled)
    }

    func finishArea(_ rect: CGRect, in view: OverlayView) {
        if returnsRegion {
            finish(.region(rect, displayID: view.capture.displayID))
            return
        }
        let pixels = CaptureGeometry.pixelRect(
            for: rect,
            overlaySize: view.bounds.size,
            imageSize: CGSize(width: view.capture.image.width, height: view.capture.image.height)
        )
        guard pixels.width >= 1, pixels.height >= 1, let image = view.capture.image.cropping(to: pixels) else {
            finish(.cancelled)
            return
        }
        finish(.area(image))
    }

    func finishWindow(at index: Int, in view: OverlayView) {
        guard windows.indices.contains(index) else { return }
        let visible = view.windowFrames[index].intersection(view.bounds)
        if returnsRegion {
            guard !visible.isEmpty else { return }
            finish(.region(visible, displayID: view.capture.displayID))
            return
        }
        let pixels = CaptureGeometry.pixelRect(
            for: visible,
            overlaySize: view.bounds.size,
            imageSize: CGSize(width: view.capture.image.width, height: view.capture.image.height)
        )
        let fallback = pixels.isEmpty ? nil : view.capture.image.cropping(to: pixels)
        finish(.window(windows[index], fallback: fallback))
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        continuation.resume(returning: outcome)
    }
}

/// A borderless panel that takes keys without activating QuickShot, so the app the
/// user was working in keeps focus once the capture ends.
final class OverlayPanel: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen, capture: DisplayCapture, windowFrames: [CGRect], controller: SelectionOverlayController) {
        overlayView = OverlayView(capture: capture, windowFrames: windowFrames, controller: controller)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        backgroundColor = .black

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let frozen = NSView(frame: container.bounds)
        frozen.autoresizingMask = [.width, .height]
        frozen.wantsLayer = true
        frozen.layer?.contents = capture.image
        frozen.layer?.contentsGravity = .resize
        overlayView.frame = container.bounds
        overlayView.autoresizingMask = [.width, .height]
        container.addSubview(frozen)
        container.addSubview(overlayView)
        contentView = container
        setFrame(screen.frame, display: true)
        initialFirstResponder = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the dimming, the selection and the hints above the frozen frame.
final class OverlayView: NSView {
    let capture: DisplayCapture
    /// Candidate window frames in this overlay's space, front to back.
    let windowFrames: [CGRect]
    private weak var controller: SelectionOverlayController?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var pointer: CGPoint?
    private var hoveredWindow: Int?

    init(capture: DisplayCapture, windowFrames: [CGRect], controller: SelectionOverlayController) {
        self.capture = capture
        self.windowFrames = windowFrames
        self.controller = controller
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Screen capture selection. Drag to select an area, press Space to pick a window, or Escape to cancel.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    func modeChanged() {
        dragStart = nil
        dragCurrent = nil
        updateHover()
        needsDisplay = true
    }

    private var selection: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CaptureGeometry.selection(from: dragStart, to: dragCurrent, in: bounds)
    }

    private func updateHover() {
        guard controller?.mode == .window, let pointer else {
            hoveredWindow = nil
            return
        }
        hoveredWindow = CaptureGeometry.frontmostIndex(containing: pointer, in: windowFrames)
    }

    private func track(_ event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if window?.isKeyWindow == false {
            window?.makeKey()
            window?.makeFirstResponder(self)
        }
        NSCursor.crosshair.set()
        updateHover()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hoveredWindow = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        track(event)
        guard let controller, let pointer else { return }
        if controller.mode == .window {
            if let hoveredWindow { controller.finishWindow(at: hoveredWindow, in: self) }
            return
        }
        dragStart = pointer
        dragCurrent = pointer
    }

    override func mouseDragged(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        if dragStart != nil { dragCurrent = pointer }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard controller?.mode == .area, dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        let rect = selection ?? .zero
        dragStart = nil
        dragCurrent = nil
        // A click without a drag is not a selection; stay open.
        if rect.width >= 4, rect.height >= 4 {
            controller?.finishArea(rect, in: self)
        } else {
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.cancel()
        case 49: controller?.toggleMode()
        default: break
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        let highlighted: CGRect?
        if controller.mode == .window {
            highlighted = hoveredWindow.map { windowFrames[$0].intersection(bounds) }
        } else {
            highlighted = selection
        }

        let dim = NSBezierPath(rect: bounds)
        if let highlighted, !highlighted.isEmpty {
            dim.append(NSBezierPath(rect: highlighted))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dim.fill()

        if let highlighted, !highlighted.isEmpty {
            if controller.mode == .window {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(rect: highlighted).fill()
            }
            let border = NSBezierPath(rect: highlighted.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = controller.mode == .window ? 2 : 1
            (controller.mode == .window ? NSColor.controlAccentColor : NSColor.white).setStroke()
            border.stroke()
            drawSizeLabel(for: highlighted)
        } else if controller.mode == .area, let pointer {
            drawCrosshair(at: pointer)
        }

        if pointer != nil || dragStart != nil {
            drawHint(controller.mode == .window
                     ? "Click a window   ·   Space: select an area   ·   Esc: cancel"
                     : controller.allowsWindowMode
                        ? "\(controller.areaHint)   ·   Space: pick a window   ·   Esc: cancel"
                        : "\(controller.areaHint)   ·   Esc: cancel")
        }
    }

    private func drawCrosshair(at point: CGPoint) {
        let lines = NSBezierPath()
        lines.move(to: CGPoint(x: point.x.rounded() + 0.5, y: 0))
        lines.line(to: CGPoint(x: point.x.rounded() + 0.5, y: bounds.maxY))
        lines.move(to: CGPoint(x: 0, y: point.y.rounded() + 0.5))
        lines.line(to: CGPoint(x: bounds.maxX, y: point.y.rounded() + 0.5))
        lines.lineWidth = 1
        NSColor.white.withAlphaComponent(0.55).setStroke()
        lines.stroke()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let pixels = CaptureGeometry.pixelRect(
            for: rect,
            overlaySize: bounds.size,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height)
        )
        let text = CaptureGeometry.sizeLabel(for: pixels) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let pill = CGSize(width: size.width + 14, height: size.height + 6)
        var origin = CGPoint(x: rect.maxX - pill.width, y: rect.maxY + 6)
        if origin.y + pill.height > bounds.maxY { origin.y = rect.maxY - pill.height - 6 }
        origin.x = max(bounds.minX + 4, min(origin.x, bounds.maxX - pill.width - 4))
        drawPill(text, attributes: attributes, in: CGRect(origin: origin, size: pill), textSize: size)
    }

    private func drawHint(_ hint: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = hint as NSString
        let size = text.size(withAttributes: attributes)
        let pill = CGSize(width: size.width + 28, height: size.height + 14)
        let rect = CGRect(x: bounds.midX - pill.width / 2, y: 44, width: pill.width, height: pill.height)
        drawPill(text, attributes: attributes, in: rect, textSize: size)
    }

    private func drawPill(_ text: NSString, attributes: [NSAttributedString.Key: Any], in rect: CGRect, textSize: CGSize) {
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }
}
