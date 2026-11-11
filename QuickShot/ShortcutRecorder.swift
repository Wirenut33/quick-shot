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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
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
