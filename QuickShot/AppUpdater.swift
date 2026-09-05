import AppKit
import Sparkle

/// Sparkle validates the signed feed and archive before replacing the app.
/// Our delegate controls only when an already downloaded update may restart us.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    var canInstall: () -> Bool = { false }
    private var pendingInstall: (() -> Void)?
    private var installTimer: Timer?
    lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var automaticUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            controller.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func start() {
        #if !DEBUG
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pendingInstall = immediateInstallHandler
        installTimer?.invalidate()
        // Do not invoke Sparkle's handler from inside its delegate callback.
        installTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.installIfIdle() }
        }
        return true
    }

    private func installIfIdle() {
        guard automaticUpdates, canInstall(), let install = pendingInstall else { return }
        installTimer?.invalidate()
        installTimer = nil
        pendingInstall = nil
        install()
    }
}
