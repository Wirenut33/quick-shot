import SwiftUI

struct SettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QuickShot").font(.title2.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Divider()
            Text("Updates").font(.headline)
            Text("QuickShot checks for updates online. Automatic updates download in the background and install after captures and annotation work are finished.")
                .fixedSize(horizontal: false, vertical: true)
            CheckForUpdatesButton()
            Text("You can turn automatic updates on or off in the camera menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)
    }
}
