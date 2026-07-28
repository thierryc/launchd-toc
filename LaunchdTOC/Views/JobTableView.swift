import SwiftUI

struct JobTableView: View {
    @Bindable var store: JobStore

    var body: some View {
        Table(store.filteredJobs, selection: $store.selectionID) {
            TableColumn("Label") { job in
                HStack(spacing: 8) {
                    Image(systemName: job.source.isAgent ? "person.crop.circle" : "gearshape.2")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.label)
                            .lineLimit(1)
                        if job.parseIssue != nil {
                            Text("Could not read property list")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .contextMenu {
                    contextMenu(for: job)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("job.\(job.label)")
                .accessibilityLabel("\(job.label), \(job.source.displayName)")
            }
            .width(min: 140, ideal: 190)

            TableColumn("State") { job in
                RuntimeStateLabel(state: job.runtimeState)
            }
            .width(min: 75, ideal: 90, max: 110)

            TableColumn("Schedule") { job in
                Text(job.scheduleSummary)
                    .foregroundStyle(job.scheduleSummary == "Not scheduled" ? .secondary : .primary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Last Run") { job in
                Text(job.lastRunText)
                    .foregroundStyle(.secondary)
            }
            .width(min: 75, ideal: 90)

            if store.showPIDColumn {
                TableColumn("PID") { job in
                    Text(job.pidText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 40, ideal: 46, max: 65)
            }
        }
        .overlay {
            if store.filteredJobs.isEmpty, !store.isRefreshing {
                ContentUnavailableView(
                    store.searchText.isEmpty ? "No Launch Jobs" : "No Results",
                    systemImage: store.searchText.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(
                        store.searchText.isEmpty
                            ? "No property lists were found in the selected locations."
                            : "Try another label, executable, or path."
                    )
                )
            }
        }
        .accessibilityIdentifier("jobs.table")
        .safeAreaInset(edge: .top, spacing: 0) {
            tableControls
        }
        .accessibilityLabel("Launch jobs")
    }

    private var tableControls: some View {
        HStack(spacing: 8) {
            Text("\(store.filteredJobs.count) \(store.filteredJobs.count == 1 ? "Job" : "Jobs")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(JobSortField.allCases) { field in
                    Button {
                        if store.sortField == field {
                            store.sortAscending.toggle()
                        } else {
                            store.sortField = field
                            store.sortAscending = true
                        }
                    } label: {
                        if store.sortField == field {
                            Label(
                                field.title,
                                systemImage: store.sortAscending ? "chevron.up" : "chevron.down"
                            )
                        } else {
                            Text(field.title)
                        }
                    }
                }
                Divider()
                Toggle("Show PID Column", isOn: $store.showPIDColumn)
            } label: {
                Label("Sort and Columns", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .help("Sort jobs and choose columns")
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func contextMenu(for job: LaunchdJob) -> some View {
        if job.source.isEditable {
            Button("Load or Unload") {
                store.selectionID = job.id
                store.loadOrUnloadSelected()
            }
            Button("Run Now") {
                store.selectionID = job.id
                store.runSelected()
            }
            Button("Restart") {
                store.selectionID = job.id
                store.restartSelected()
            }
            Divider()
            Button("Edit…") {
                store.presentEditor(for: job)
            }
            if job.runtimeState == .disabled {
                Button("Enable") {
                    Task { await store.perform(.enable, on: job) }
                }
            } else {
                Button("Disable") {
                    store.requestDisable(job)
                }
            }
            Divider()
            Button("Move to Trash…", role: .destructive) {
                store.requestTrash(job)
            }
        } else {
            Button("Read-Only Location") {}
                .disabled(true)
        }
    }
}

struct RuntimeStateLabel: View {
    let state: JobRuntimeState

    var body: some View {
        Label(state.label, systemImage: state.symbolName)
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(state.label)
    }

    private var color: Color {
        switch state {
        case .running: .green
        case .waiting: .blue
        case .failed: .red
        case .disabled, .unloaded, .unknown: .secondary
        }
    }
}
