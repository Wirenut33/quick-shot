// Disposable integration-test host. Never added to the QuickShot app target.
import AppKit

@main
struct UpdaterHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let updater = AppUpdater.shared
        // Test starts busy. Removing this marker simulates finishing an annotation.
        updater.canInstall = { !FileManager.default.fileExists(atPath: "/tmp/quickshot-updater-busy") }
        updater.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            try? version.write(toFile: "/tmp/quickshot-updater-host-version.txt", atomically: true, encoding: .utf8)
            if updater.controller.updater.canCheckForUpdates {
                updater.controller.updater.checkForUpdatesInBackground()
            }
        }
        app.run()
    }
}
