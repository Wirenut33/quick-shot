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
        do {
            try LoginItemManager.shared.ensureEnabled()
        } catch {
            NSLog("QuickShot could not register as a login item: \(error.localizedDescription)")
        }
        statusBarController = StatusBarController()
        AppUpdater.shared.canInstall = { [weak self] in
            self?.statusBarController?.canInstallUpdate == true
        }
        if !ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("-test") || $0 == "--capture-full" }) {
            AppUpdater.shared.start()
        }

        // Hidden smoke-test hook used to validate the installed app's complete
        // capture-to-editor flow without relying on menu-bar coordinates.
        if ProcessInfo.processInfo.arguments.contains("--collection-capture-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusBarController?.testCollectionCapture()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--editor-smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.statusBarController?.openEditorForTesting()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--capture-full") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.statusBarController?.captureForTesting(.fullScreen)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
