import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Launchd TOC")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("A native utility for inspecting and managing user launch agents.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Divider()
            Text("Copyright © 2026 Thierry Charbonnel. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Independent implementation. No source, assets, interface copy, or icons from azu/launchd-ui are included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 460)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

struct UpdateAvailableView: View {
    @Environment(\.dismiss) private var dismiss
    let release: GitHubRelease
    let hasDirectDownload: Bool
    let openUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("A new version is available")
                        .font(.title3.weight(.semibold))
                    Text(release.name ?? release.tagName)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(release.body?.isEmpty == false ? release.body ?? "" : "No release notes were provided.")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 180)

            HStack {
                Spacer()
                Button("Not Now") { dismiss() }
                Button(hasDirectDownload ? "Download Universal DMG" : "Open Release Page") {
                    openUpdate()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 360)
    }
}
