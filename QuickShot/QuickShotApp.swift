//
//  QuickShotApp.swift
//  QuickShot
//
//  Created by Michael Morale on 12/21/25.
//

import SwiftUI

@main
struct QuickShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
