import AppKit
import SwiftUI

struct JobDetailView: View {
    let job: LaunchdJob
    @Bindable var store: JobStore
    @State private var logStream: LogStream = .standardOutput
    @State private var logText = ""
    @State private var logMessage: String?
    @State private var isLoadingLog = false
    @State private var showsClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                Divider()
                DetailSection(title: "Overview") {
                    detailRow("Runtime State") {
                        RuntimeStateLabel(state: job.runtimeState)
                    }
                    detailRow("Process ID", value: job.pidText)
                    detailRow("Last Exit Code", value: lastExitCode)
                    detailRow("Last Run", value: job.lastRunText)
                    detailRow("Enabled", value: job.runtimeState == .disabled ? "No" : "Yes")
                }
                DetailSection(title: "Configuration") {
                    detailRow("Executable", value: job.configuration.executable ?? "—")
                    detailRow(
                        "Arguments",
                        value: job.configuration.programArguments.isEmpty
                            ? "—"
                            : job.configuration.programArguments.joined(separator: "  ")
                    )
                    detailRow("Working Directory", value: job.configuration.workingDirectory ?? "—")
                    detailRow(
                        "Environment",
                        value: job.configuration.environment.isEmpty
                            ? "—"
                            : job.configuration.environment.keys.sorted().joined(separator: ", ")
                    )
                    detailRow("Run at Load", value: job.configuration.runAtLoad ? "Yes" : "No")
                    detailRow("Keep Alive", value: keepAliveDescription)
                }
                DetailSection(title: "Schedule") {
                    detailRow("Summary", value: job.scheduleSummary)
                    if job.predictedRuns.isEmpty {
                        detailRow("Next Run", value: "No predictable run")
                    } else {
                        ForEach(Array(job.predictedRuns.enumerated()), id: \.offset) { index, date in
                            detailRow(
                                index == 0 ? "Next Run" : "",
                                value: date.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }
                }
                logsSection
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(job.label)
        .task(id: logStream) {
            await refreshLog()
        }
        .confirmationDialog(
            "Clear this log file?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) {
                Task { await clearLog() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently empties the selected log file. The launch agent itself is not changed.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 64, height: 64)
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(job.label)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Text(job.source.displayName)
                        .foregroundStyle(.secondary)
                    RuntimeStateLabel(state: job.runtimeState)
                }
                Text(job.plistURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(job.label), \(job.source.displayName), \(job.runtimeState.label), \(job.plistURL.path)"
        )
    }

    private var logsSection: some View {
        DetailSection(title: "Logs") {
            HStack {
                Picker("Log Stream", selection: $logStream) {
                    ForEach(LogStream.allCases) { stream in
                        Text(stream.title).tag(stream)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)

                Spacer()

                Button {
                    Task { await refreshLog() }
                } label: {
                    Label("Refresh Log", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoadingLog || selectedLogURL == nil)
                .help("Refresh log")

                Button {
                    if let url = selectedLogURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Log", systemImage: "arrow.up.forward.app")
                        .labelStyle(.iconOnly)
                }
                .disabled(selectedLogURL == nil)
                .help("Open log in the default app")

                Button {
                    showsClearConfirmation = true
                } label: {
                    Label("Clear Log", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(!job.source.isEditable || selectedLogURL == nil)
                .help("Clear log")
            }

            if let logMessage {
                Text(logMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(logText.isEmpty ? "No log content." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(minHeight: 150, idealHeight: 220)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 0.5)
            }
            .accessibilityLabel("\(logStream.title) log")
        }
    }

    private var selectedLogURL: URL? {
        let path = logStream == .standardOutput
            ? job.configuration.standardOutPath
            : job.configuration.standardErrorPath
        guard let path, !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    private var lastExitCode: String {
        guard case let .failed(exitCode) = job.runtimeState else { return "—" }
        return String(exitCode)
    }

    private var keepAliveDescription: String {
        switch job.configuration.keepAlive {
        case true: "Yes"
        case false: "No"
        case nil: "Advanced condition"
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        detailRow(title) {
            Text(value)
                .foregroundStyle(value == "—" ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    private func detailRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func refreshLog() async {
        isLoadingLog = true
        defer { isLoadingLog = false }
        do {
            logText = try await store.logTailer.tail(url: selectedLogURL)
            logMessage = nil
        } catch LogTailerError.unavailable {
            logText = ""
            logMessage = "No path is configured for \(logStream.title)."
        } catch {
            logText = ""
            logMessage = error.localizedDescription
        }
    }

    private func clearLog() async {
        do {
            try await store.logTailer.clear(url: selectedLogURL)
            await refreshLog()
        } catch {
            logMessage = error.localizedDescription
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { Divider() }
    }
}
