//
//  RecordingOverlays.swift
//  QuickShot
//

@preconcurrency import AVFoundation
import AppKit

/// A round, floating camera preview. It sits on screen like any window, so the screen
/// recording picks it up: drag it anywhere, double-click to change its size.
@MainActor
final class CameraBubble {
    private static let diameters: [CGFloat] = [140, 200, 280]

    private let session = AVCaptureSession()
    private let panel: NSPanel
    private let bubbleView: BubbleView
    private let sessionQueue = DispatchQueue(label: "QuickShot.camera")

    /// Lists the cameras QuickShot can show, built-in first.
    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    init(deviceID: String?, frame: CGRect) throws {
        let cameras = Self.availableCameras()
        guard let device = cameras.first(where: { $0.uniqueID == deviceID })
                ?? AVCaptureDevice.default(for: .video) ?? cameras.first else {
            throw RecordingError.cameraUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecordingError.failed("The camera could not be opened: \(error.localizedDescription)")
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecordingError.cameraUnavailable
        }
        session.addInput(input)
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        // People expect to see themselves as in a mirror.
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        bubbleView = BubbleView(preview: preview)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = bubbleView
        bubbleView.onDoubleClick = { [weak self] in self?.cycleSize() }
        panel.setAccessibilityLabel("Camera preview. Drag to move, double-click to resize.")
    }

    func show() {
        panel.orderFrontRegardless()
        // Starting the camera blocks, so it happens off the main thread.
        nonisolated(unsafe) let session = session
        sessionQueue.async { session.startRunning() }
    }

    func close() {
        panel.orderOut(nil)
        nonisolated(unsafe) let session = session
        sessionQueue.async { session.stopRunning() }
    }

    private func cycleSize() {
        let current = panel.frame
        let index = Self.diameters.firstIndex { $0 > current.width + 1 } ?? 0
        let diameter = Self.diameters[index]
        // Grow and shrink around the centre so the bubble stays where it was put.
        let frame = CGRect(x: current.midX - diameter / 2, y: current.midY - diameter / 2, width: diameter, height: diameter)
        panel.setFrame(frame, display: true, animate: true)
    }
}

private final class BubbleView: NSView {
    var onDoubleClick: (() -> Void)?
    private let preview: AVCaptureVideoPreviewLayer

    init(preview: AVCaptureVideoPreviewLayer) {
        self.preview = preview
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 3
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// A dashed outline drawn just outside the area being recorded, so it never appears in
/// the recording itself. It ignores the mouse.
@MainActor
final class RecordingFrame {
    private static let thickness: CGFloat = 4
    private let panel: NSPanel

    /// `region` is in AppKit's global coordinates.
    init(region: CGRect) {
        let frame = region.insetBy(dx: -Self.thickness, dy: -Self.thickness)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FrameView(thickness: Self.thickness)
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }

    private final class FrameView: NSView {
        let thickness: CGFloat

        init(thickness: CGFloat) {
            self.thickness = thickness
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            // Centre the stroke in the margin so none of it reaches the recorded area.
            let path = NSBezierPath(rect: bounds.insetBy(dx: thickness / 2, dy: thickness / 2))
            path.lineWidth = thickness - 1
            NSColor.black.withAlphaComponent(0.5).setStroke()
            path.stroke()
            path.lineWidth = 2
            path.setLineDash([8, 6], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            path.stroke()
        }
    }
}

/// "3, 2, 1" in the middle of the area about to be recorded. It closes before
/// recording starts, so it never appears in the movie.
@MainActor
enum RecordingCountdown {
    /// Returns false when cancelled with `cancel()`.
    static func run(over region: CGRect, seconds: Int = 3) async -> Bool {
        let size = CGSize(width: 150, height: 150)
        let panel = NSPanel(
            contentRect: CGRect(x: region.midX - size.width / 2, y: region.midY - size.height / 2, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // A solid dark backing keeps the white digit readable in Light and Dark Mode.
        let background = NSView(frame: CGRect(origin: .zero, size: size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        background.layer?.cornerRadius = 30
        background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 84, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: (size.height - 104) / 2, width: size.width, height: 104)
        background.addSubview(label)
        panel.contentView = background

        cancelled = false
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        for remaining in stride(from: seconds, to: 0, by: -1) {
            label.stringValue = "\(remaining)"
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: "\(remaining)", .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if cancelled { return false }
            }
        }
        return !cancelled
    }

    private static var cancelled = false

    static func cancel() { cancelled = true }
}
