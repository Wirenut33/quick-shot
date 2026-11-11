//
//  SettingsView.swift
//  QuickShot
//

import AVFoundation
import AppKit
import SwiftUI

/// Lets views open app windows that the menu bar controller owns.
enum AppCommands {
    @MainActor static var showWelcome: () -> Void = {}
}

enum AppInfo {
    static let privacyPolicyURL = URL(string: "https://github.com/Wirenut33/quick-shot/blob/main/PRIVACY.md")
    static let supportURL = URL(string: "https://github.com/Wirenut33/quick-shot/issues")

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}

struct SettingsView: View {
    var showWelcome: () -> Void = { AppCommands.showWelcome() }

    var body: some View {
        TabView {
            GeneralSettings(showWelcome: showWelcome)
                .tabItem { Label("General", systemImage: "gearshape") }
            RecordingSettings()
                .tabItem { Label("Recording", systemImage: "record.circle") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(.top, 8)
        .frame(width: 520, height: 520)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = LoginItemManager.shared.isEnabled
    @State private var loginProblem: String?
    let showWelcome: () -> Void

    var body: some View {
        Form {
            Section("After a capture") {
                Toggle("Open the editor", isOn: $settings.annotateMode)
                Text(settings.annotateMode
                     ? "Each capture opens for markup. Turn this off to copy captures straight to the clipboard."
                     : "Captures go straight to the clipboard, or to the Snapshot Collection while collecting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Saving") {
                LabeledContent("Save folder") {
                    HStack {
                        Text(settings.saveFolderName ?? "Ask each time")
                            .foregroundStyle(settings.saveFolderURL == nil ? .secondary : .primary)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                        if settings.saveFolderURL != nil {
                            Button("Reset") { settings.clearSaveFolder() }
                        }
                    }
                }
                Text(settings.saveFolderURL == nil
                     ? "Choose a folder to save with ⌘S in one step."
                     : "⌘S in the editor saves here without asking. ⇧⌘S asks where to save.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Copy the file path after saving", isOn: $settings.copyPathMode)
            }

            Section("Startup") {
                Toggle("Open QuickShot at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginProblem {
                    Text(loginProblem).font(.caption).foregroundStyle(.orange)
                }
                Button("Show Welcome Guide…", action: showWelcome)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItemManager.shared.isEnabled }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where QuickShot saves screenshots"
        if let current = settings.saveFolderURL { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url {
            settings.setSaveFolder(url)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.shared.setEnabled(enabled)
            loginProblem = LoginItemManager.shared.requiresApproval
                ? "Approve QuickShot in System Settings > General > Login Items."
                : nil
        } catch {
            loginProblem = error.localizedDescription
        }
        launchAtLogin = LoginItemManager.shared.isEnabled
    }
}

private struct RecordingSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var microphones: [AVCaptureDevice] = []
    @State private var cameras: [AVCaptureDevice] = []

    var body: some View {
        Form {
            Section {
                Toggle("Record the microphone", isOn: $settings.recordMicrophone)
                Picker("Microphone", selection: $settings.microphoneID) {
                    Text("System default").tag(String?.none)
                    ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                .disabled(!settings.recordMicrophone)
                permissionNote(for: .audio, enabled: settings.recordMicrophone, name: "Microphone", pane: "Privacy_Microphone")
                Toggle("Record system audio", isOn: $settings.recordSystemAudio)
            } header: {
                Text("Sound")
            } footer: {
                Text("System audio is the sound your Mac plays, such as an app or a video. QuickShot's own sounds are left out.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show the camera", isOn: $settings.recordCamera)
                Picker("Camera", selection: $settings.cameraID) {
                    Text("System default").tag(String?.none)
                    ForEach(cameras, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                .disabled(!settings.recordCamera)
                permissionNote(for: .video, enabled: settings.recordCamera, name: "Camera", pane: "Privacy_Camera")
            } header: {
                Text("Camera")
            } footer: {
                Text("Your camera appears in a round bubble that is recorded with the screen. Drag it to move it; double-click it to change its size.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Recording") {
                Toggle("Highlight clicks", isOn: $settings.recordShowsClicks)
                Toggle("Count down before recording", isOn: $settings.recordCountdown)
                Text("Click the stop button in the menu bar, or press the recording shortcut again, to finish. The recording then opens for trimming and export as a movie or GIF.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDevices)
    }

    @ViewBuilder
    private func permissionNote(for mediaType: AVMediaType, enabled: Bool, name: String, pane: String) -> some View {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        if enabled, status == .denied || status == .restricted {
            HStack {
                Text("\(name) access is turned off for QuickShot.")
                    .font(.caption).foregroundStyle(.orange)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func loadDevices() {
        microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
        cameras = CameraBubble.availableCameras()
    }
}

struct ShortcutList: View {
    @Binding var shortcuts: [CaptureAction: Shortcut]
    var unavailable: Set<CaptureAction> = []
    /// Plain rows for use outside a grouped form.
    var plain = false

    var body: some View {
        ForEach(CaptureAction.allCases) { action in
            if plain {
                HStack(alignment: .firstTextBaseline) {
                    label(for: action)
                    Spacer(minLength: 12)
                    recorder(for: action)
                }
            } else {
                LabeledContent {
                    recorder(for: action)
                } label: {
                    label(for: action)
                }
            }
        }
    }

    private func label(for action: CaptureAction) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(action.title)
            Text(action.detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func recorder(for action: CaptureAction) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ShortcutRecorder(title: action.title, shortcut: shortcuts[action]) { shortcut in
                if let shortcut {
                    for (other, existing) in shortcuts where other != action && existing == shortcut {
                        shortcuts[other] = nil
                    }
                }
                shortcuts[action] = shortcut
            }
            if unavailable.contains(action), shortcuts[action] != nil {
                Text("Not available. Another app may be using it.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct ShortcutSettings: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ShortcutList(
                    shortcuts: Binding(
                        get: { settings.shortcuts },
                        set: { updated in
                            for action in CaptureAction.allCases where settings.shortcuts[action] != updated[action] {
                                settings.setShortcut(updated[action], for: action)
                            }
                        }
                    ),
                    unavailable: settings.unavailableShortcuts
                )
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("These work in any app. Click a shortcut, then press the keys you want.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Use Suggested Shortcuts") {
                    for action in CaptureAction.allCases {
                        if let suggested = action.suggestedShortcut { settings.setShortcut(suggested, for: action) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QuickShot").font(.title3.bold())
                        Text("Version \(AppInfo.version) (\(AppInfo.build))").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Privacy") {
                Text("QuickShot collects nothing. Captures, recognised text and snapshots stay on this Mac, and the app makes no network connections of its own for them.")
                    .fixedSize(horizontal: false, vertical: true)
                if let url = AppInfo.privacyPolicyURL {
                    Link("Privacy Policy", destination: url)
                }
                if let url = AppInfo.supportURL {
                    Link("Support", destination: url)
                }
            }
            #if !APPSTORE
            Section("Updates") {
                AutomaticUpdatesToggle()
                CheckForUpdatesButton()
            }
            #endif
        }
        .formStyle(.grouped)
    }
}
