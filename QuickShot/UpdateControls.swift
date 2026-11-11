#if !APPSTORE
import Combine
import Sparkle
import SwiftUI

/// Tracks Sparkle's state so checks cannot be started twice while one is running.
final class UpdateAvailability: ObservableObject {
    @Published var canCheckForUpdates = false

    init() {
        AppUpdater.shared.controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesButton: View {
    @StateObject private var availability = UpdateAvailability()

    var body: some View {
        Button("Check for Updates…") {
            AppUpdater.shared.checkForUpdates()
        }
        .disabled(!availability.canCheckForUpdates)
    }
}

struct AutomaticUpdatesToggle: View {
    @State private var enabled = AppUpdater.shared.automaticUpdates

    var body: some View {
        Toggle("Download and install updates automatically", isOn: Binding(
            get: { enabled },
            set: { value in
                AppUpdater.shared.automaticUpdates = value
                enabled = AppUpdater.shared.automaticUpdates
            }
        ))
    }
}
#endif
