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
