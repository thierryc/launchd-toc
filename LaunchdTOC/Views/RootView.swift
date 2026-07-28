import SwiftUI

struct RootView: View {
    @Bindable var store: JobStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 260)
        } content: {
            JobTableView(store: store)
                .navigationSplitViewColumnWidth(min: 410, ideal: 500)
        } detail: {
            if let job = store.selectedJob {
                JobDetailView(job: job, store: store)
                    .id(job.id)
            } else {
                ContentUnavailableView(
                    "Select a Launch Job",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Choose a job to inspect its configuration and runtime state.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search Jobs")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.presentNewAgent()
                } label: {
                    Label("New Agent", systemImage: "plus")
                }
                .accessibilityIdentifier("toolbar.newAgent")
                .help("Create a user launch agent")

                Button {
                    store.loadOrUnloadSelected()
                } label: {
                    Label(loadUnloadTitle, systemImage: loadUnloadSymbol)
                }
                .accessibilityIdentifier("toolbar.loadUnload")
                .disabled(!selectedJobIsEditable)
                .help(loadUnloadTitle)

                Button {
                    store.runSelected()
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                .accessibilityIdentifier("toolbar.runNow")
                .disabled(!selectedJobIsEditable)
                .help("Run the selected agent now")

                Button {
                    store.restartSelected()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("toolbar.restart")
                .disabled(!selectedJobIsEditable)
                .help("Restart the selected agent")

                Button {
                    store.presentEditor()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .accessibilityIdentifier("toolbar.edit")
                .disabled(!selectedJobIsEditable)
                .help("Edit the selected user agent")

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("toolbar.refresh")
                .disabled(store.isRefreshing)
                .help("Refresh launch jobs")
            }
        }
        .task {
            if store.jobs.isEmpty {
                await store.refresh()
            }
        }
        .sheet(item: $store.editorRequest) { request in
            AgentEditorView(job: request.job, store: store)
        }
        .sheet(isPresented: $store.showsAbout) {
            AboutView()
        }
        .sheet(
            isPresented: Binding(
                get: { store.availableRelease != nil },
                set: { if !$0 { store.availableRelease = nil } }
            )
        ) {
            if let release = store.availableRelease {
                UpdateAvailableView(
                    release: release,
                    hasDirectDownload: store.availableDownloadURL != nil,
                    openUpdate: store.openAvailableUpdate
                )
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { store.confirmationRequest != nil },
                set: { if !$0 { store.confirmationRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            confirmationButtons
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Launchd TOC",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(
            store.noticeTitle ?? "Launchd TOC",
            isPresented: Binding(
                get: { store.noticeMessage != nil },
                set: {
                    if !$0 {
                        store.noticeTitle = nil
                        store.noticeMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.noticeTitle = nil
                store.noticeMessage = nil
            }
        } message: {
            Text(store.noticeMessage ?? "")
        }
    }

    private var selectedJobIsEditable: Bool {
        store.selectedJob?.source.isEditable == true
    }

    private var loadUnloadTitle: String {
        switch store.selectedJob?.runtimeState {
        case .running, .waiting, .failed:
            "Unload"
        default:
            "Load"
        }
    }

    private var loadUnloadSymbol: String {
        loadUnloadTitle == "Unload" ? "stop.fill" : "arrow.up.circle"
    }

    private var confirmationTitle: String {
        switch store.confirmationRequest {
        case .enableAndLoad: "Enable and load this agent?"
        case .loadAndRun: "Load and run this agent?"
        case .enableLoadAndRun: "Enable, load, and run this agent?"
        case .disable: "Disable this running agent?"
        case .trash: "Move this agent to the Trash?"
        case nil: ""
        }
    }

    private var confirmationMessage: String {
        switch store.confirmationRequest {
        case .enableAndLoad:
            "Loading a disabled agent requires clearing its persistent disabled override."
        case .loadAndRun:
            "The agent is currently unloaded. It must be loaded before it can run."
        case .enableLoadAndRun:
            "The agent is disabled. Launchd TOC will enable it, load it, and request an immediate run."
        case .disable:
            "You can keep the current process running or unload it immediately."
        case .trash:
            "The agent will be unloaded, any disabled override will be cleared, and its property list will be moved to the macOS Trash."
        case nil:
            ""
        }
    }

    @ViewBuilder
    private var confirmationButtons: some View {
        switch store.confirmationRequest {
        case let .enableAndLoad(job):
            Button("Enable and Load") {
                store.confirmationRequest = nil
                Task { await store.enableAndLoad(job) }
            }
        case let .loadAndRun(job):
            Button("Load and Run") {
                store.confirmationRequest = nil
                Task { await store.loadAndRun(job) }
            }
        case let .enableLoadAndRun(job):
            Button("Enable, Load, and Run") {
                store.confirmationRequest = nil
                Task { await store.enableLoadAndRun(job) }
            }
        case let .disable(job):
            Button("Disable and Unload", role: .destructive) {
                store.confirmationRequest = nil
                Task { await store.disableAndUnload(job, unload: true) }
            }
            Button("Disable Only") {
                store.confirmationRequest = nil
                Task { await store.disableAndUnload(job, unload: false) }
            }
        case let .trash(job):
            Button("Move to Trash", role: .destructive) {
                store.confirmationRequest = nil
                Task { await store.moveToTrash(job) }
            }
        case nil:
            EmptyView()
        }
        Button("Cancel", role: .cancel) {
            store.confirmationRequest = nil
        }
    }
}
