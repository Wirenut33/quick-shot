//
//  AppDelegate.swift
//  QuickShot
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Launching at login is the user's choice, made in the welcome window or Settings.
        let controller = StatusBarController()
        statusBarController = controller

        let arguments = ProcessInfo.processInfo.arguments
        var diagnosticLaunch = false

        #if DEBUG
        if arguments.contains("--capture-self-test") {
            diagnosticLaunch = true
            controller.runCaptureSelfTest()
        } else if arguments.contains("--show-settings") {
            diagnosticLaunch = true
            controller.showSettingsForTesting()
        }
        #endif

        #if !APPSTORE
        // Smoke-test hooks used to validate an installed direct build's capture-to-editor
        // flow without relying on menu bar coordinates. Not present in the App Store build.
        if arguments.contains("--collection-capture-test") {
            diagnosticLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.testCollectionCapture() }
        } else if arguments.contains("--editor-smoke-test") {
            diagnosticLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.openEditorForTesting() }
        } else if arguments.contains("--recording-self-test") {
            diagnosticLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.runRecordingSelfTest() }
        } else if arguments.contains("--record-full") || arguments.contains("--record-selection") {
            diagnosticLaunch = true
            let action: CaptureAction = arguments.contains("--record-full") ? .recordScreen : .recordSelection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.captureForTesting(action) }
        } else if arguments.contains("--capture-full") {
            diagnosticLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { controller.captureForTesting(.fullScreen) }
        }

        AppUpdater.shared.canInstall = { [weak controller] in controller?.canInstallUpdate == true }
        if !diagnosticLaunch {
            AppUpdater.shared.start()
        }
        #endif

        if !diagnosticLaunch {
            controller.showWelcomeIfNeeded()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        statusBarController?.shouldTerminate() ?? .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
