import SwiftUI

struct SidebarView: View {
    @Bindable var store: JobStore

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("Library") {
                sidebarRow(.all)
                sidebarRow(.userAgents)
                sidebarRow(.globalAgents)
                sidebarRow(.daemons)
            }

            Section("Status") {
                sidebarRow(.running)
                sidebarRow(.attention)
                sidebarRow(.disabled)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Launchd TOC")
        .accessibilityLabel("Launch job categories")
    }

    private func sidebarRow(_ filter: SidebarFilter) -> some View {
        Label {
            HStack {
                Text(filter.title)
                Spacer()
                Text(store.count(for: filter), format: .number)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: filter.symbolName)
        }
        .tag(filter)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sidebar.\(filter.rawValue)")
        .accessibilityLabel("\(filter.title), \(store.count(for: filter)) jobs")
    }
}
