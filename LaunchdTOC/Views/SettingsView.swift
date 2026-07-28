import SwiftUI

struct SettingsView: View {
    @Bindable var store: JobStore

    var body: some View {
        Form {
            Section("Inventory") {
                Toggle("Show Apple Services", isOn: $store.showAppleServices)
                    .onChange(of: store.showAppleServices) {
                        Task { await store.refresh() }
                    }
                Text(
                    "Includes read-only jobs from /System/Library/LaunchAgents and /System/Library/LaunchDaemons."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Table") {
                Toggle("Show PID column", isOn: $store.showPIDColumn)
            }

            Section("Privacy") {
                Text(
                    "Launchd TOC makes no automatic network requests. Help → Check for Updates is the only network feature."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Launchd TOC Settings")
        .padding(.vertical, 8)
    }
}
