//
//  WelcomeView.swift
//  QuickShot
//

import AppKit
import Combine
import SwiftUI

/// First-run guide. A menu bar app shows no window of its own, so this explains where
/// QuickShot lives, walks through the Screen Recording permission, and offers shortcuts.
/// It is marked complete only when the user presses the final button, so it returns
/// after the relaunch macOS asks for when Screen Recording is granted.
struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var granted = CGPreflightScreenCaptureAccess()
    @State private var requested = false
    @State private var drafts: [CaptureAction: Shortcut]
    @State private var launchAtLogin = LoginItemManager.shared.isEnabled
    let finish: () -> Void

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(finish: @escaping () -> Void) {
        self.finish = finish
        var initial = AppSettings.shared.shortcuts
        // Suggestions are offered once; reopening the guide shows what is in use.
        if initial.isEmpty, !AppSettings.shared.welcomeCompleted {
            for action in CaptureAction.allCases {
                if let suggested = action.suggestedShortcut { initial[action] = suggested }
            }
        }
        _drafts = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to QuickShot").font(.title.bold())
                    HStack(spacing: 5) {
                        Text("QuickShot lives in the menu bar. Look for")
                        Image(systemName: "camera.viewfinder").accessibilityLabel("the camera icon")
                        Text("at the top of your screen.")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text(granted ? "Screen Recording is allowed" : "Allow Screen Recording")
                            .font(.headline)
                    } icon: {
                        Image(systemName: granted ? "checkmark.circle.fill" : "1.circle.fill")
                            .foregroundStyle(granted ? .green : .accentColor)
                    }
                    if granted {
                        Text("You're set. QuickShot can capture your screen.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("macOS needs your permission before any app can capture the screen. QuickShot only captures when you ask it to, and nothing leaves this Mac.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Allow Screen Recording…") {
                                requested = true
                                if !CGRequestScreenCaptureAccess() { openScreenRecordingSettings() }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Open System Settings", action: openScreenRecordingSettings)
                        }
                        if requested {
                            Text("Turn on QuickShot in the list. If macOS offers Quit & Reopen, accept it. This guide comes back afterwards.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("Choose your shortcuts").font(.headline)
                    } icon: {
                        Image(systemName: "2.circle.fill").foregroundStyle(Color.accentColor)
                    }
                    Text("These work in any app once you continue. Change or remove any of them now or later in Settings.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ShortcutList(shortcuts: $drafts, plain: true)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Toggle("Open QuickShot at login", isOn: $launchAtLogin)

            HStack {
                Text(granted ? "" : "You can finish now and allow Screen Recording at your first capture.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(granted ? "Start Using QuickShot" : "Continue", action: complete)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(26)
        .frame(width: 560)
        .onReceive(refresh) { _ in granted = CGPreflightScreenCaptureAccess() }
    }

    private func complete() {
        for action in CaptureAction.allCases {
            settings.setShortcut(drafts[action], for: action)
        }
        if launchAtLogin != LoginItemManager.shared.isEnabled {
            do {
                try LoginItemManager.shared.setEnabled(launchAtLogin)
            } catch {
                NSLog("QuickShot could not update the login item: \(error.localizedDescription)")
            }
        }
        settings.welcomeCompleted = true
        finish()
    }

    private func openScreenRecordingSettings() {
        requested = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
