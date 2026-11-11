//
//  ShortcutRecorder.swift
//  QuickShot
//

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted with `object: true` when a recorder starts listening and `false` when it stops,
    /// so global shortcuts can be paused and the pressed keys reach the recorder.
    static let shortcutRecordingChanged = Notification.Name("QuickShotShortcutRecordingChanged")
}

/// A button that records the next key combination the user presses.
struct ShortcutRecorder: View {
    let title: String
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void

    @State private var recording = false
    @State private var problem: String?
    @State private var monitor: Any?
    @State private var resignObserver: NSObjectProtocol?
    @State private var recordingWindow: NSWindow?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 6) {
                Button(action: { recording ? stop() : start() }) {
                    Text(recording ? "Type shortcut…" : (shortcut?.displayString ?? "Record Shortcut"))
                        .frame(minWidth: 118)
                }
                .accessibilityLabel("Shortcut for \(title)")
                .accessibilityValue(recording ? "Recording" : (shortcut?.displayString ?? "None"))
                .help(recording ? "Press Escape to stop recording" : "Click, then press the keys to use")

                Button {
                    problem = nil
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut for \(title)")
                .opacity(shortcut == nil || recording ? 0 : 1)
                .disabled(shortcut == nil || recording)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        problem = nil
        recording = true
        NotificationCenter.default.post(name: .shortcutRecordingChanged, object: true)
        // The click that started recording made this window key.
        let window = NSApp.keyWindow
        recordingWindow = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Keys typed in another QuickShot window belong to that window.
            guard event.window === window else {
                stop()
                return event
            }
            handle(event)
            return nil
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { stop() }
            }
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        recordingWindow = nil
        NotificationCenter.default.post(name: .shortcutRecordingChanged, object: false)
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Shortcut.allowedModifiers)
        if event.keyCode == 53, modifiers.isEmpty {
            stop()
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            problem = "Include ⌘, ⌃ or ⌥."
            return
        }
        guard !HotKeyCenter.isReservedBySystem(candidate) else {
            problem = "macOS already uses \(candidate.displayString)."
            return
        }
        problem = nil
        stop()
        onChange(candidate)
    }
}
