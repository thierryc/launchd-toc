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
    @State private var showsArgumentVector = true
    @State private var showsExactValues = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                Divider()

                DetailSection(title: "At a Glance") {
                    behaviorSummaryCard
                    detailRow("Runtime State") {
                        RuntimeStateLabel(state: job.runtimeState)
                    }
                    if case .running = job.runtimeState {
                        detailRow("Process ID", value: job.pidText, monospaced: true)
                    }
                    if case let .failed(exitCode) = job.runtimeState {
                        detailRow("Last Exit Code", value: String(exitCode), monospaced: true)
                    }
                    if job.lastRun != nil {
                        detailRow("Last Run", value: job.lastRunText)
                    }
                    detailRow("Enabled", value: job.runtimeState == .disabled ? "No" : "Yes")
                }

                DetailSection(title: "Launch Behavior") {
                    detailRow("Run When Loaded", value: job.configuration.runAtLoad ? "Yes" : "No")
                    detailRow("Keep Running", value: job.configuration.keepAliveDescription)

                    if let repeatingSchedule = job.configuration.repeatingScheduleDescription {
                        detailRow("Launch Schedule", value: repeatingSchedule)
                        ForEach(Array(job.predictedRuns.enumerated()), id: \.offset) { index, date in
                            detailRow(
                                index == 0 ? "Next Predicted Launch" : "",
                                value: date.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    } else {
                        emptyMessage(
                            "No repeating launchd interval or calendar schedule is configured."
                        )
                    }

                    if let throttleInterval = job.configuration.throttleInterval {
                        detailRow(
                            "Minimum Restart Delay",
                            value: LaunchDurationFormatter.description(seconds: throttleInterval)
                        )
                        helpText(
                            "ThrottleInterval limits how frequently launchd starts the process. "
                                + "It does not control how often the application performs work."
                        )
                    }

                    if let processType = job.configuration.processType {
                        detailRow("Process Type", value: processType.displayName)
                        helpText(processType.explanation)
                    }
                }

                DetailSection(title: "Execution") {
                    commandCard
                    detailRow("Executable", value: job.configuration.executable ?? "Not configured", monospaced: true)
                    detailRow("Executable Source", value: job.configuration.executableSourceDescription)

                    DisclosureGroup(
                        "Command Arguments (\(job.configuration.commandArguments.count))",
                        isExpanded: $showsArgumentVector
                    ) {
                        if job.configuration.commandArguments.isEmpty {
                            emptyMessage("No command arguments are configured.")
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(
                                    Array(job.configuration.commandArguments.enumerated()),
                                    id: \.offset
                                ) { index, argument in
                                    indexedValueRow(index: index + 1, value: argument)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }

                DetailSection(title: "Environment and Files") {
                    if let workingDirectory = job.configuration.workingDirectory {
                        pathRow("Working Directory", path: workingDirectory)
                    }
                    if let standardOutPath = job.configuration.standardOutPath {
                        pathRow("Standard Output", path: standardOutPath)
                    }
                    if let standardErrorPath = job.configuration.standardErrorPath {
                        pathRow("Standard Error", path: standardErrorPath)
                    }

                    if job.configuration.workingDirectory == nil,
                       job.configuration.standardOutPath == nil,
                       job.configuration.standardErrorPath == nil
                    {
                        emptyMessage("No working directory or output files are configured.")
                    }

                    if job.configuration.environment.isEmpty {
                        emptyMessage("No environment variables are configured.")
                    } else {
                        Text("Environment Variables")
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 6)
                        ForEach(job.configuration.environment.keys.sorted(), id: \.self) { key in
                            detailRow(key, value: job.configuration.environment[key] ?? "", monospaced: true)
                        }
                    }
                }

                DetailSection(title: "Technical Details") {
                    DisclosureGroup("Exact launchd values", isExpanded: $showsExactValues) {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Property List Format", value: job.configuration.originalFormat.rawValue.uppercased())
                            if let program = job.configuration.program {
                                detailRow("Program", value: program, monospaced: true)
                            } else {
                                detailRow("Program", value: "Not present")
                            }
                            Text("ProgramArguments (\(job.configuration.programArguments.count))")
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 4)
                            ForEach(
                                Array(job.configuration.programArguments.enumerated()),
                                id: \.offset
                            ) { index, argument in
                                indexedValueRow(index: index, value: argument)
                            }

                            if !job.configuration.advancedValues.isEmpty {
                                Text("Preserved Properties")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.top, 6)
                                ForEach(job.configuration.advancedValues.keys.sorted(), id: \.self) { key in
                                    detailRow(
                                        key,
                                        value: job.configuration.advancedValues[key]?.displayString ?? "",
                                        monospaced: true
                                    )
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    helpText(
                        "These values come from the launchd property list. Application log output "
                            + "is shown separately below and is never treated as configuration."
                    )
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

    private var behaviorSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.configuration.launchBehaviorSummary)
                .font(.body.weight(.medium))
            if let repeatingSchedule = job.configuration.repeatingScheduleDescription {
                Label(repeatingSchedule, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("No repeating launchd schedule", systemImage: "calendar.badge.minus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.behaviorSummary")
    }

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Invocation Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyToPasteboard(job.configuration.commandPreview)
                } label: {
                    Label("Copy Invocation", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy invocation preview")
                .disabled(job.configuration.commandPreview.isEmpty)
            }
            Text(
                job.configuration.commandPreview.isEmpty
                    ? "No executable is configured."
                    : job.configuration.commandPreview
            )
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(job.configuration.commandPreview.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
        .padding(.bottom, 6)
    }

    private var logsSection: some View {
        DetailSection(title: "Application Output") {
            Text("stdout and stderr are produced by the application and are not launchd configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
            .accessibilityLabel("\(logStream.title) application output")
        }
    }

    private var selectedLogURL: URL? {
        let path = logStream == .standardOutput
            ? job.configuration.standardOutPath
            : job.configuration.standardErrorPath
        guard let path, !path.isEmpty else { return nil }
        return URL(filePath: path)
    }

    private func detailRow(
        _ title: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        detailRow(title) {
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(value == "Not configured" ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
    }

    private func detailRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func indexedValueRow(index: Int, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(index))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Argument \(index), \(value)")
    }

    private func pathRow(_ title: String, path: String) -> some View {
        detailRow(title) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    copyToPasteboard(path)
                } label: {
                    Label("Copy \(title)", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy \(title.lowercased())")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                } label: {
                    Label("Reveal \(title)", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .disabled(!FileManager.default.fileExists(atPath: path))
            }
        }
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
    }

    private func helpText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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
