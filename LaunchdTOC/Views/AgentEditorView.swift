import SwiftUI

private struct EnvironmentRow: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

struct AgentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let job: LaunchdJob?
    @Bindable var store: JobStore
    @State private var draft: JobConfiguration
    @State private var environmentRows: [EnvironmentRow]
    @State private var isSaving = false

    init(job: LaunchdJob?, store: JobStore) {
        self.job = job
        self.store = store
        let initial = job?.configuration ?? JobConfiguration(label: "", keepAlive: false)
        _draft = State(initialValue: initial)
        _environmentRows = State(
            initialValue: initial.environment.keys.sorted().map {
                EnvironmentRow(key: $0, value: initial.environment[$0] ?? "")
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Identity") {
                    TextField("Label", text: $draft.label)
                        .textContentType(.none)
                        .accessibilityIdentifier("editor.label")
                        .accessibilityHint("Reverse-domain launchd label")
                    Text(job?.plistURL.path ?? "~/Library/LaunchAgents/<label>.plist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Section("Executable") {
                    TextField("Program", text: optionalTextBinding(\.program))
                    editableStringRows(
                        title: "Program Arguments",
                        values: $draft.programArguments,
                        newValue: ""
                    )
                }

                Section("Launch Behavior") {
                    Toggle("Run at Load", isOn: $draft.runAtLoad)
                    if draft.keepAlive == nil {
                        LabeledContent("Keep Alive") {
                            Text("Advanced condition preserved")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle(
                            "Keep Alive",
                            isOn: Binding(
                                get: { draft.keepAlive ?? false },
                                set: { draft.keepAlive = $0 }
                            )
                        )
                    }
                    TextField(
                        "Start Interval (seconds)",
                        value: $draft.startInterval,
                        format: .number
                    )
                }

                Section("Calendar Schedule") {
                    ForEach($draft.calendarSchedules) { $schedule in
                        HStack {
                            optionalNumberField("Month", value: $schedule.month)
                            optionalNumberField("Day", value: $schedule.day)
                            optionalNumberField("Weekday", value: $schedule.weekday)
                            optionalNumberField("Hour", value: $schedule.hour)
                            optionalNumberField("Minute", value: $schedule.minute)
                            Button(role: .destructive) {
                                draft.calendarSchedules.removeAll { $0.id == schedule.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove calendar entry")
                        }
                    }
                    Button {
                        draft.calendarWasArray = true
                        draft.calendarSchedules.append(CalendarSchedule())
                    } label: {
                        Label("Add Calendar Entry", systemImage: "plus")
                    }
                }

                Section("Environment and Paths") {
                    TextField("Working Directory", text: optionalTextBinding(\.workingDirectory))
                    TextField("Standard Output Path", text: optionalTextBinding(\.standardOutPath))
                    TextField("Standard Error Path", text: optionalTextBinding(\.standardErrorPath))

                    LabeledContent("Environment Variables") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach($environmentRows) { $row in
                                HStack {
                                    TextField("Name", text: $row.key)
                                    TextField("Value", text: $row.value)
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
                }

                if !draft.advancedValues.isEmpty {
                    Section("Advanced Properties") {
                        Text(
                            "These existing values cannot be represented by the form. They remain unchanged when you save."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ForEach(draft.advancedValues.keys.sorted(), id: \.self) { key in
                            LabeledContent(key) {
                                Text(draft.advancedValues[key]?.displayString ?? "")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if job != nil {
                    Text("The original format and unknown keys will be preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task { await save(reload: false) }
                }
                .accessibilityIdentifier("editor.save")
                .disabled(!isValid || isSaving)
                Button("Save & Reload") {
                    Task { await save(reload: true) }
                }
                .accessibilityIdentifier("editor.saveReload")
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding(16)
        }
        .frame(width: 760, height: 720)
        .navigationTitle(job == nil ? "New Agent" : "Edit Agent")
    }

    private var isValid: Bool {
        PlistRepository.isValidLabel(draft.label)
            && draft.executable?.isEmpty == false
            && (draft.startInterval == nil || draft.startInterval ?? 0 > 0)
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

    private func optionalNumberField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, value: value, format: .number)
            .frame(minWidth: 58)
            .accessibilityLabel(title)
    }

    private func editableStringRows(
        title: String,
        values: Binding<[String]>,
        newValue: String
    ) -> some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(values.wrappedValue.indices, id: \.self) { index in
                    HStack {
                        TextField("Argument \(index + 1)", text: values[index])
                        Button(role: .destructive) {
                            values.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove argument \(index + 1)")
                    }
                }
                Button {
                    values.wrappedValue.append(newValue)
                } label: {
                    Label("Add Argument", systemImage: "plus")
                }
            }
        }
    }

    private func save(reload: Bool) async {
        isSaving = true
        defer { isSaving = false }
        var updated = draft
        var environment: [String: String] = [:]
        for row in environmentRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                environment[key] = row.value
            }
        }
        updated.environment = environment
        if await store.save(updated, existingJob: job, reload: reload) {
            dismiss()
        }
    }
}
