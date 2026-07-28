import AppKit
import SwiftUI

private struct EditableStringRow: Identifiable, Hashable {
    let id = UUID()
    var value: String
}

private struct EnvironmentRow: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
}

private enum AgentEditorTab: String, CaseIterable, Identifiable {
    case general
    case launch
    case environment
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .launch: "Launch & Schedule"
        case .environment: "Environment & Logs"
        case .advanced: "Advanced"
        }
    }
}

struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let job: LaunchdJob?
    @Bindable var store: JobStore

    private let initialConfiguration: JobConfiguration
    private let usesProgramKey: Bool

    @State private var draft: JobConfiguration
    @State private var executableText: String
    @State private var argumentRows: [EditableStringRow]
    @State private var environmentRows: [EnvironmentRow]
    @State private var intervalEnabled: Bool
    @State private var intervalAmount: Int
    @State private var intervalUnit: LaunchDurationUnit
    @State private var throttleEnabled: Bool
    @State private var throttleAmount: Int
    @State private var selectedTab: AgentEditorTab = .general
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false

    init(job: LaunchdJob?, store: JobStore) {
        self.job = job
        self.store = store

        let initial = job?.configuration ?? JobConfiguration(label: "", keepAlive: false)
        initialConfiguration = initial
        usesProgramKey = job == nil || initial.program != nil

        _draft = State(initialValue: initial)
        _executableText = State(initialValue: initial.program ?? initial.programArguments.first ?? "")

        let editableArguments = usesProgramKey
            ? initial.programArguments
            : Array(initial.programArguments.dropFirst())
        _argumentRows = State(
            initialValue: editableArguments.map { EditableStringRow(value: $0) }
        )
        _environmentRows = State(
            initialValue: initial.environment.keys.sorted().map {
                EnvironmentRow(key: $0, value: initial.environment[$0] ?? "")
            }
        )

        let interval = initial.startInterval ?? 60
        let intervalFit = LaunchDurationUnit.bestFit(seconds: interval)
        _intervalEnabled = State(initialValue: initial.startInterval != nil)
        _intervalAmount = State(initialValue: intervalFit.amount)
        _intervalUnit = State(initialValue: intervalFit.unit)

        _throttleEnabled = State(initialValue: initial.throttleInterval != nil)
        _throttleAmount = State(initialValue: initial.throttleInterval ?? 10)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalForm
                case .launch:
                    launchForm
                case .environment:
                    environmentForm
                case .advanced:
                    advancedForm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            editorFooter
        }
        .frame(width: 860, height: 720)
        .navigationTitle(job == nil ? "New Agent" : "Edit Agent")
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes to this launch agent have not been saved.")
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(job == nil ? "New User Agent" : "Edit User Agent")
                    .font(.headline)
                Text("Configure what runs, when launchd starts it, and where its output goes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Editor Section", selection: $selectedTab) {
                ForEach(AgentEditorTab.allCases) { tab in
                    Text(tab.title)
                        .tag(tab)
                        .accessibilityIdentifier("editor.tab.\(tab.rawValue)")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 490)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var generalForm: some View {
        Form {
            Section("Identity") {
                fullWidthTextField("Label", text: $draft.label)
                    .textContentType(.none)
                    .accessibilityIdentifier("editor.label")
                    .accessibilityHint("Reverse-domain launchd label")

                LabeledContent("Property List") {
                    Text(job?.plistURL.path ?? "~/Library/LaunchAgents/<label>.plist")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Command") {
                fullWidthTextField("Executable", text: $executableText)
                    .accessibilityIdentifier("editor.executable")

                LabeledContent("Stored As") {
                    Text(usesProgramKey ? "Program" : "ProgramArguments[0]")
                        .foregroundStyle(.secondary)
                }

                commandPreview

                LabeledContent(usesProgramKey ? "Argument Vector" : "Command Arguments") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(argumentRows.enumerated()), id: \.element.id) { index, row in
                            argumentEditorRow(index: index, rowID: row.id)
                        }

                        Button {
                            argumentRows.append(EditableStringRow(value: ""))
                        } label: {
                            Label("Add Argument", systemImage: "plus")
                        }
                        .accessibilityIdentifier("editor.addArgument")
                    }
                }

                Text(argumentHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var launchForm: some View {
        Form {
            Section("Launch Behavior") {
                Toggle("Run when loaded", isOn: $draft.runAtLoad)
                    .help("RunAtLoad launches the job once when it is loaded, typically at login.")
                Text("RunAtLoad launches the job once when it is loaded, typically at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if draft.keepAlive == nil {
                    LabeledContent("Keep running") {
                        Text("Conditional rules preserved")
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "This job uses a KeepAlive dictionary. Its exact conditional rules are "
                            + "preserved in Advanced."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Toggle(
                        "Keep running",
                        isOn: Binding(
                            get: { draft.keepAlive ?? false },
                            set: { draft.keepAlive = $0 }
                        )
                    )
                    .help("KeepAlive asks launchd to relaunch the process when it exits.")
                    Text("KeepAlive asks launchd to relaunch the process when it exits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Repeating Launch Interval") {
                Toggle("Repeat on a launchd interval", isOn: $intervalEnabled)
                    .accessibilityIdentifier("editor.intervalEnabled")

                if intervalEnabled {
                    LabeledContent("Repeat every") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("Amount", value: $intervalAmount, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                                .accessibilityLabel("Interval amount")

                            Picker("Unit", selection: $intervalUnit) {
                                ForEach(LaunchDurationUnit.allCases) { unit in
                                    Text(unit.title).tag(unit)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }

                    if let seconds = intervalSeconds, seconds > 0 {
                        Text(
                            "Launchd property: StartInterval = \(seconds) seconds "
                                + "(\(LaunchDurationFormatter.description(seconds: seconds)))."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if draft.keepAlive == true {
                        Label(
                            "Keep running is enabled, so the process may already be alive when "
                                + "an interval trigger occurs.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No StartInterval value will be written to the launchd property list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calendar Triggers") {
                ForEach(Array(draft.calendarSchedules.indices), id: \.self) { index in
                    calendarEntryEditor(index: index)
                }

                Button {
                    draft.calendarWasArray = true
                    draft.calendarSchedules.append(CalendarSchedule())
                } label: {
                    Label("Add Calendar Trigger", systemImage: "plus")
                }
            }

            Section("Restart and Resource Policy") {
                Toggle("Override minimum restart delay", isOn: $throttleEnabled)
                    .accessibilityIdentifier("editor.throttleEnabled")

                if throttleEnabled {
                    LabeledContent("Minimum restart delay") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("Seconds", value: $throttleAmount, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .accessibilityLabel("Minimum restart delay in seconds")
                                .accessibilityIdentifier("editor.throttleAmount")
                            Text("seconds")
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)
                                .accessibilityIdentifier("editor.throttleUnit")
                                .accessibilityLabel("seconds")
                        }
                        .fixedSize()
                    }
                    Text(
                        "ThrottleInterval limits how frequently launchd starts the process. "
                            + "It does not control the application's own work interval."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Picker("Process type", selection: $draft.processType) {
                    Text("System default").tag(nil as JobProcessType?)
                    ForEach(processTypeOptions) { processType in
                        Text(processType.displayName).tag(processType as JobProcessType?)
                    }
                }

                if let processType = draft.processType {
                    Text(processType.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var environmentForm: some View {
        Form {
            Section("Working Directory and Output") {
                fullWidthTextField(
                    "Working Directory",
                    text: optionalTextBinding(\.workingDirectory)
                )
                fullWidthTextField(
                    "Standard Output Path",
                    text: optionalTextBinding(\.standardOutPath)
                )
                fullWidthTextField(
                    "Standard Error Path",
                    text: optionalTextBinding(\.standardErrorPath)
                )

                Text(
                    "The output paths receive the application's stdout and stderr. "
                        + "Their contents are not treated as launchd configuration."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Environment Variables") {
                ForEach($environmentRows) { $row in
                    HStack {
                        TextField("Name", text: $row.key)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230)
                        TextField("Value", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Button(role: .destructive) {
                            environmentRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove environment variable")
                    }
                }

                Button {
                    environmentRows.append(EnvironmentRow(key: "", value: ""))
                } label: {
                    Label("Add Variable", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var advancedForm: some View {
        Form {
            Section("Exact Executable Representation") {
                LabeledContent("Executable source") {
                    Text(usesProgramKey ? "Program key" : "First ProgramArguments value")
                }
                LabeledContent("Program") {
                    Text(preparedConfiguration.program ?? "Not present")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(preparedConfiguration.program == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                }

                LabeledContent(
                    "ProgramArguments (\(preparedConfiguration.programArguments.count))"
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if preparedConfiguration.programArguments.isEmpty {
                            Text("Not present")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(
                                Array(preparedConfiguration.programArguments.enumerated()),
                                id: \.offset
                            ) { index, argument in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(String(index))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(argument)
                                        .font(.system(.callout, design: .monospaced))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                Text(
                    "The guided Command editor writes back to this same representation without "
                        + "changing the executable source or argument order."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Property List") {
                LabeledContent("Format") {
                    Text(draft.originalFormat.rawValue.uppercased())
                }
                LabeledContent("Known fields") {
                    Text("\(JobConfiguration.supportedKeys.count)")
                }
                LabeledContent("Preserved fields") {
                    Text("\(draft.advancedValues.count)")
                }
            }

            if !draft.advancedValues.isEmpty {
                Section("Preserved Properties") {
                    Text(
                        "These values are not represented by the guided form. "
                            + "They remain unchanged when you save."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(draft.advancedValues.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) {
                            Text(draft.advancedValues[key]?.displayString ?? "")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var editorFooter: some View {
        HStack {
            Group {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving…")
                        .foregroundStyle(.secondary)
                } else if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if hasChanges {
                    Text("Unsaved changes")
                        .foregroundStyle(.secondary)
                } else {
                    Text(job == nil ? "Enter the required values to create an agent." : "No changes")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            Spacer()

            Button("Cancel") {
                cancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Save Only") {
                Task { await save(reload: false) }
            }
            .accessibilityIdentifier("editor.save")
            .help("Save the property list without reloading the agent")
            .disabled(!isValid || isSaving || !hasChanges)

            Button("Save & Apply") {
                Task { await save(reload: true) }
            }
            .accessibilityIdentifier("editor.saveReload")
            .keyboardShortcut(.defaultAction)
            .help("Save the property list and reload the agent so changes take effect")
            .disabled(!isValid || isSaving || !hasChanges)
        }
        .padding(16)
    }

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Invocation Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyToPasteboard(preparedConfiguration.commandPreview)
                } label: {
                    Label("Copy Invocation", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy invocation preview")
                .disabled(preparedConfiguration.commandPreview.isEmpty)
            }
            Text(
                preparedConfiguration.commandPreview.isEmpty
                    ? "Enter an executable to build the invocation preview."
                    : preparedConfiguration.commandPreview
            )
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(preparedConfiguration.commandPreview.isEmpty ? .secondary : .primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
    }

    private var intervalSeconds: Int? {
        intervalEnabled ? intervalUnit.seconds(for: intervalAmount) : nil
    }

    private var preparedConfiguration: JobConfiguration {
        var updated = draft
        if usesProgramKey {
            updated.program = executableText
            updated.programArguments = argumentRows.map(\.value)
        } else {
            updated.program = nil
            updated.programArguments = [executableText] + argumentRows.map(\.value)
        }

        var environment: [String: String] = [:]
        for row in environmentRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                environment[key] = row.value
            }
        }
        updated.environment = environment
        updated.startInterval = intervalSeconds
        updated.throttleInterval = throttleEnabled ? throttleAmount : nil
        return updated
    }

    private var hasChanges: Bool {
        preparedConfiguration != initialConfiguration
    }

    private var isValid: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        guard PlistRepository.isValidLabel(draft.label) else {
            return "Enter a valid reverse-domain label."
        }
        guard !executableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter an executable."
        }
        if intervalEnabled {
            guard intervalAmount > 0, intervalSeconds != nil else {
                return "Enter a valid repeating interval greater than zero."
            }
        }
        if throttleEnabled, throttleAmount <= 0 {
            return "Enter a minimum restart delay greater than zero."
        }
        if let calendarError {
            return calendarError
        }

        let environmentKeys = environmentRows
            .map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if Set(environmentKeys).count != environmentKeys.count {
            return "Environment variable names must be unique."
        }
        return nil
    }

    private var calendarError: String? {
        let bounds: [(String, KeyPath<CalendarSchedule, Int?>, ClosedRange<Int>)] = [
            ("minute", \.minute, 0...59),
            ("hour", \.hour, 0...23),
            ("day", \.day, 1...31),
            ("weekday", \.weekday, 0...7),
            ("month", \.month, 1...12)
        ]
        for schedule in draft.calendarSchedules {
            for (name, keyPath, range) in bounds {
                if let value = schedule[keyPath: keyPath], !range.contains(value) {
                    return "The calendar \(name) is outside its allowed range."
                }
            }
        }
        return nil
    }

    private var processTypeOptions: [JobProcessType] {
        guard let processType = draft.processType,
              !JobProcessType.knownCases.contains(processType)
        else {
            return JobProcessType.knownCases
        }
        return [processType] + JobProcessType.knownCases
    }

    private var argumentHelp: String {
        if usesProgramKey {
            "This job stores its executable in Program. ProgramArguments is the exact argv "
                + "vector; its first value is argv[0]. Argument order is preserved."
        } else {
            "This job stores its executable as ProgramArguments[0]. The rows above are the "
                + "remaining command arguments, in order."
        }
    }

    private func fullWidthTextField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private func optionalTextBinding(
        _ keyPath: WritableKeyPath<JobConfiguration, String?>
    ) -> Binding<String> {
        Binding {
            draft[keyPath: keyPath] ?? ""
        } set: { value in
            draft[keyPath: keyPath] = value.isEmpty ? nil : value
        }
    }

    private func argumentEditorRow(index: Int, rowID: UUID) -> some View {
        HStack {
            Text(argumentLabel(index: index))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)

            TextField(
                argumentLabel(index: index),
                text: Binding {
                    argumentRows.first { $0.id == rowID }?.value ?? ""
                } set: { newValue in
                    guard let rowIndex = argumentRows.firstIndex(where: { $0.id == rowID }) else {
                        return
                    }
                    argumentRows[rowIndex].value = newValue
                }
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))

            Button {
                moveArgument(at: index, offset: -1)
            } label: {
                Label("Move \(argumentLabel(index: index)) Up", systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                moveArgument(at: index, offset: 1)
            } label: {
                Label("Move \(argumentLabel(index: index)) Down", systemImage: "arrow.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(index == argumentRows.count - 1)

            Button(role: .destructive) {
                argumentRows.removeAll { $0.id == rowID }
            } label: {
                Label("Remove \(argumentLabel(index: index))", systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }

    private func argumentLabel(index: Int) -> String {
        if usesProgramKey, index == 0 {
            return "argv[0]"
        }
        return "Argument \(usesProgramKey ? index : index + 1)"
    }

    private func moveArgument(at index: Int, offset: Int) {
        let destination = index + offset
        guard argumentRows.indices.contains(index), argumentRows.indices.contains(destination) else {
            return
        }
        argumentRows.swapAt(index, destination)
    }

    private func calendarEntryEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trigger \(index + 1)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(role: .destructive) {
                    draft.calendarSchedules.remove(at: index)
                } label: {
                    Label("Remove calendar trigger \(index + 1)", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Picker(
                    "Weekday",
                    selection: $draft.calendarSchedules[index].weekday
                ) {
                    Text("Any weekday").tag(nil as Int?)
                    ForEach(0...7, id: \.self) { value in
                        Text(weekdayName(value)).tag(value as Int?)
                    }
                }

                Picker(
                    "Month",
                    selection: $draft.calendarSchedules[index].month
                ) {
                    Text("Any month").tag(nil as Int?)
                    ForEach(1...12, id: \.self) { value in
                        Text(Calendar.current.monthSymbols[value - 1]).tag(value as Int?)
                    }
                }
            }

            HStack {
                optionalNumberField(
                    "Day",
                    value: $draft.calendarSchedules[index].day
                )
                optionalNumberField(
                    "Hour",
                    value: $draft.calendarSchedules[index].hour
                )
                optionalNumberField(
                    "Minute",
                    value: $draft.calendarSchedules[index].minute
                )
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        }
    }

    private func weekdayName(_ value: Int) -> String {
        if value == 0 {
            return "Sunday (0)"
        }
        if value == 7 {
            return "Sunday (7)"
        }
        let names = DateFormatter().weekdaySymbols ?? Calendar.current.weekdaySymbols
        return names[value]
    }

    private func optionalNumberField(_ title: String, value: Binding<Int?>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .accessibilityLabel(title)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func cancel() {
        if hasChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save(reload: Bool) async {
        isSaving = true
        defer { isSaving = false }
        if await store.save(preparedConfiguration, existingJob: job, reload: reload) {
            dismiss()
        }
    }
}
