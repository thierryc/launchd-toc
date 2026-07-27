import AppKit
import Foundation
import Observation

enum JobSortField: String, CaseIterable, Identifiable, Sendable {
    case label
    case state
    case schedule
    case lastRun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .label: "Label"
        case .state: "State"
        case .schedule: "Schedule"
        case .lastRun: "Last Run"
        }
    }
}

enum JobStoreError: LocalizedError {
    case noSelection
    case readOnly

    var errorDescription: String? {
        switch self {
        case .noSelection: "Select a launch job first."
        case .readOnly: "Global and Apple launch jobs are read-only."
        }
    }
}

struct EditorRequest: Identifiable {
    let id = UUID()
    let job: LaunchdJob?
}

enum JobConfirmation: Identifiable {
    case enableAndLoad(LaunchdJob)
    case loadAndRun(LaunchdJob)
    case enableLoadAndRun(LaunchdJob)
    case disable(LaunchdJob)
    case trash(LaunchdJob)

    var id: String {
        switch self {
        case let .enableAndLoad(job): "enable-load:\(job.id)"
        case let .loadAndRun(job): "load-run:\(job.id)"
        case let .enableLoadAndRun(job): "enable-load-run:\(job.id)"
        case let .disable(job): "disable:\(job.id)"
        case let .trash(job): "trash:\(job.id)"
        }
    }
}

@MainActor
@Observable
final class JobStore {
    private(set) var jobs: [LaunchdJob] = []
    private(set) var isRefreshing = false
    private(set) var isCheckingForUpdates = false
    var searchText = ""
    var errorMessage: String?
    var noticeTitle: String?
    var noticeMessage: String?
    var availableRelease: GitHubRelease?
    var availableDownloadURL: URL?
    var editorRequest: EditorRequest?
    var confirmationRequest: JobConfirmation?
    var showsAbout = false

    var selectionID: LaunchdJob.ID? {
        didSet { defaults.set(selectionID, forKey: PreferenceKey.selectionID) }
    }

    var sidebarSelection: SidebarFilter {
        didSet { defaults.set(sidebarSelection.rawValue, forKey: PreferenceKey.sidebarSelection) }
    }

    var showAppleServices: Bool {
        didSet { defaults.set(showAppleServices, forKey: PreferenceKey.showAppleServices) }
    }

    var showPIDColumn: Bool {
        didSet { defaults.set(showPIDColumn, forKey: PreferenceKey.showPIDColumn) }
    }

    var sortField: JobSortField {
        didSet { defaults.set(sortField.rawValue, forKey: PreferenceKey.sortField) }
    }

    var sortAscending: Bool {
        didSet { defaults.set(sortAscending, forKey: PreferenceKey.sortAscending) }
    }

    private let repository: PlistRepository
    private let launchctl: any LaunchctlRunning
    private let schedulePreview: SchedulePreview
    let logTailer: LogTailer
    private let updateChecker: UpdateChecker
    private let defaults: UserDefaults
    private let userID: uid_t

    init(
        repository: PlistRepository = PlistRepository(),
        launchctl: any LaunchctlRunning = LaunchctlClient(),
        schedulePreview: SchedulePreview = SchedulePreview(),
        logTailer: LogTailer = LogTailer(),
        updateChecker: UpdateChecker = UpdateChecker(),
        defaults: UserDefaults = .standard,
        userID: uid_t = getuid(),
        initialJobs: [LaunchdJob] = []
    ) {
        self.repository = repository
        self.launchctl = launchctl
        self.schedulePreview = schedulePreview
        self.logTailer = logTailer
        self.updateChecker = updateChecker
        self.defaults = defaults
        self.userID = userID
        jobs = initialJobs

        selectionID = defaults.string(forKey: PreferenceKey.selectionID)
        sidebarSelection = SidebarFilter(
            rawValue: defaults.string(forKey: PreferenceKey.sidebarSelection) ?? ""
        ) ?? .all
        showAppleServices = defaults.bool(forKey: PreferenceKey.showAppleServices)
        showPIDColumn = defaults.object(forKey: PreferenceKey.showPIDColumn) as? Bool ?? true
        sortField = JobSortField(
            rawValue: defaults.string(forKey: PreferenceKey.sortField) ?? ""
        ) ?? .label
        sortAscending = defaults.object(forKey: PreferenceKey.sortAscending) as? Bool ?? true
    }

    var selectedJob: LaunchdJob? {
        jobs.first { $0.id == selectionID }
    }

    var filteredJobs: [LaunchdJob] {
        let filtered = jobs.filter(matchesSidebar).filter(matchesSearch)
        return filtered.sorted { first, second in
            let result: ComparisonResult
            switch sortField {
            case .label:
                result = first.label.localizedStandardCompare(second.label)
            case .state:
                result = first.stateSortValue.localizedStandardCompare(second.stateSortValue)
            case .schedule:
                result = first.scheduleSummary.localizedStandardCompare(second.scheduleSummary)
            case .lastRun:
                result = compare(first.lastRun, second.lastRun)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    func count(for filter: SidebarFilter) -> Int {
        jobs.filter { matches($0, filter: filter) }.count
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let showApple = showAppleServices
        let repository = repository
        let scanned = await Task.detached(priority: .userInitiated) {
            repository.scan(showAppleServices: showApple)
        }.value

        let guiDomain = JobSource.userAgent.domain(userID: userID)
        let systemDomain = JobSource.daemon.domain(userID: userID)
        async let disabledGUI = launchctl.disabledLabels(in: guiDomain)
        async let disabledSystem = launchctl.disabledLabels(in: systemDomain)
        let (disabledAgents, disabledDaemons) = await (disabledGUI, disabledSystem)

        var initialStates: [String: JobRuntimeState] = [:]
        var runtimeJobs: [LaunchdJob] = []
        for job in scanned where job.parseIssue == nil {
            let isDisabled = job.source.isAgent
                ? disabledAgents.contains(job.label)
                : disabledDaemons.contains(job.label)
            if isDisabled {
                initialStates[job.id] = .disabled
            } else {
                runtimeJobs.append(job)
            }
        }

        let runtimeByID = await withTaskGroup(
            of: (String, JobRuntimeState).self,
            returning: [String: JobRuntimeState].self
        ) { group in
            var iterator = runtimeJobs.makeIterator()
            let concurrencyLimit = min(12, runtimeJobs.count)
            for _ in 0..<concurrencyLimit {
                if let job = iterator.next() {
                    group.addTask { [launchctl] in
                        (job.id, await launchctl.runtimeState(for: job))
                    }
                }
            }

            var states = initialStates
            for await (id, state) in group {
                states[id] = state
                if let job = iterator.next() {
                    group.addTask { [launchctl] in
                        (job.id, await launchctl.runtimeState(for: job))
                    }
                }
            }
            return states
        }

        jobs = scanned.map { job in
            var updated = job
            if let state = runtimeByID[job.id] {
                updated.runtimeState = state
            }
            updated.scheduleSummary = schedulePreview.summary(for: job.configuration)
            updated.predictedRuns = schedulePreview.nextRuns(for: job.configuration)
            return updated
        }

        if let selectionID, jobs.contains(where: { $0.id == selectionID }) {
            return
        }
        selectionID = filteredJobs.first?.id ?? jobs.first?.id
    }

    func perform(_ action: LaunchctlAction, on job: LaunchdJob? = nil) async {
        do {
            let target = try editableJob(job)
            try await launchctl.perform(action, on: target)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentNewAgent() {
        editorRequest = EditorRequest(job: nil)
    }

    func presentEditor(for job: LaunchdJob? = nil) {
        guard let target = job ?? selectedJob, target.source.isEditable else {
            errorMessage = (job ?? selectedJob) == nil
                ? JobStoreError.noSelection.localizedDescription
                : JobStoreError.readOnly.localizedDescription
            return
        }
        editorRequest = EditorRequest(job: target)
    }

    func loadOrUnloadSelected() {
        guard let job = selectedJob else {
            errorMessage = JobStoreError.noSelection.localizedDescription
            return
        }
        guard job.source.isEditable else {
            errorMessage = JobStoreError.readOnly.localizedDescription
            return
        }
        switch job.runtimeState {
        case .disabled:
            confirmationRequest = .enableAndLoad(job)
        case .unloaded:
            Task { await perform(.load, on: job) }
        case .running, .waiting, .failed:
            Task { await perform(.unload, on: job) }
        case .unknown:
            Task { await perform(.load, on: job) }
        }
    }

    func runSelected() {
        guard let job = selectedJob else {
            errorMessage = JobStoreError.noSelection.localizedDescription
            return
        }
        guard job.source.isEditable else {
            errorMessage = JobStoreError.readOnly.localizedDescription
            return
        }
        switch job.runtimeState {
        case .disabled:
            confirmationRequest = .enableLoadAndRun(job)
        case .unloaded:
            confirmationRequest = .loadAndRun(job)
        default:
            Task { await perform(.run, on: job) }
        }
    }

    func restartSelected() {
        guard let job = selectedJob else {
            errorMessage = JobStoreError.noSelection.localizedDescription
            return
        }
        guard job.source.isEditable else {
            errorMessage = JobStoreError.readOnly.localizedDescription
            return
        }
        switch job.runtimeState {
        case .disabled:
            confirmationRequest = .enableLoadAndRun(job)
        case .unloaded:
            confirmationRequest = .loadAndRun(job)
        default:
            Task { await perform(.restart, on: job) }
        }
    }

    func requestDisable(_ job: LaunchdJob? = nil) {
        guard let target = job ?? selectedJob else {
            errorMessage = JobStoreError.noSelection.localizedDescription
            return
        }
        guard target.source.isEditable else {
            errorMessage = JobStoreError.readOnly.localizedDescription
            return
        }
        if case .running = target.runtimeState {
            confirmationRequest = .disable(target)
        } else {
            Task { await perform(.disable, on: target) }
        }
    }

    func requestTrash(_ job: LaunchdJob? = nil) {
        guard let target = job ?? selectedJob else {
            errorMessage = JobStoreError.noSelection.localizedDescription
            return
        }
        guard target.source.isEditable else {
            errorMessage = JobStoreError.readOnly.localizedDescription
            return
        }
        confirmationRequest = .trash(target)
    }

    func enableAndLoad(_ job: LaunchdJob) async {
        do {
            let target = try editableJob(job)
            try await launchctl.perform(.enable, on: target)
            try await launchctl.perform(.load, on: target)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableLoadAndRun(_ job: LaunchdJob) async {
        do {
            let target = try editableJob(job)
            try await launchctl.perform(.enable, on: target)
            try await launchctl.perform(.load, on: target)
            try await launchctl.perform(.run, on: target)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAndRun(_ job: LaunchdJob) async {
        do {
            let target = try editableJob(job)
            try await launchctl.perform(.load, on: target)
            try await launchctl.perform(.run, on: target)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disableAndUnload(_ job: LaunchdJob, unload: Bool) async {
        do {
            let target = try editableJob(job)
            try await launchctl.perform(.disable, on: target)
            if unload {
                try await launchctl.perform(.unload, on: target)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(
        _ configuration: JobConfiguration,
        existingJob: LaunchdJob?,
        reload: Bool
    ) async -> Bool {
        do {
            let destination: URL
            if let existingJob {
                guard existingJob.source.isEditable else { throw JobStoreError.readOnly }
                destination = existingJob.plistURL
                if reload, existingJob.runtimeState != .unloaded, existingJob.runtimeState != .disabled {
                    try? await launchctl.perform(.unload, on: existingJob)
                }
            } else {
                destination = try repository.newAgentURL(label: configuration.label)
            }

            let savedURL = try await repository.save(configuration, to: destination)
            if reload {
                let savedJob = LaunchdJob(
                    plistURL: savedURL,
                    source: .userAgent,
                    configuration: configuration
                )
                try await launchctl.perform(.load, on: savedJob)
            }
            await refresh()
            let savedID = "\(JobSource.userAgent.rawValue):\(savedURL.standardizedFileURL.path)"
            selectionID = savedID
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveToTrash(_ job: LaunchdJob) async {
        do {
            let target = try editableJob(job)
            switch target.runtimeState {
            case .running, .waiting:
                try await launchctl.perform(.unload, on: target)
            default:
                break
            }
            if target.runtimeState == .disabled {
                try await launchctl.perform(.enable, on: target)
            }
            _ = try repository.trash(target.plistURL)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let current = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        do {
            switch try await updateChecker.check(currentVersion: current) {
            case let .updateAvailable(release, downloadURL):
                availableRelease = release
                availableDownloadURL = downloadURL
            case .upToDate:
                noticeTitle = "You’re up to date"
                noticeMessage = "Launchd TOC \(current) is the latest stable release."
            case .noRelease:
                noticeTitle = "No stable release"
                noticeMessage = "There is no stable GitHub release available yet."
            }
        } catch {
            errorMessage = "Update check failed. \(error.localizedDescription)"
        }
    }

    func openAvailableUpdate() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(availableDownloadURL ?? release.htmlURL)
    }

    private func editableJob(_ supplied: LaunchdJob?) throws -> LaunchdJob {
        guard let job = supplied ?? selectedJob else { throw JobStoreError.noSelection }
        guard job.source.isEditable else { throw JobStoreError.readOnly }
        return job
    }

    private func matchesSidebar(_ job: LaunchdJob) -> Bool {
        matches(job, filter: sidebarSelection)
    }

    private func matches(_ job: LaunchdJob, filter: SidebarFilter) -> Bool {
        switch filter {
        case .all:
            true
        case .userAgents:
            job.source == .userAgent
        case .globalAgents:
            job.source == .globalAgent || job.source == .appleAgent
        case .daemons:
            job.source == .daemon || job.source == .appleDaemon
        case .running:
            if case .running = job.runtimeState { true } else { false }
        case .attention:
            if case .failed = job.runtimeState { true }
            else { job.parseIssue != nil || job.runtimeState == .unknown }
        case .disabled:
            job.runtimeState == .disabled || job.runtimeState == .unloaded
        }
    }

    private func matchesSearch(_ job: LaunchdJob) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return job.label.localizedCaseInsensitiveContains(needle)
            || job.plistURL.path.localizedCaseInsensitiveContains(needle)
            || (job.configuration.executable?.localizedCaseInsensitiveContains(needle) ?? false)
    }

    private func compare(_ first: Date?, _ second: Date?) -> ComparisonResult {
        switch (first, second) {
        case let (first?, second?): first.compare(second)
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        }
    }
}

private enum PreferenceKey {
    static let selectionID = "selectionID"
    static let sidebarSelection = "sidebarSelection"
    static let showAppleServices = "showAppleServices"
    static let showPIDColumn = "showPIDColumn"
    static let sortField = "sortField"
    static let sortAscending = "sortAscending"
}
