import SwiftUI

@main
struct LaunchdTOCApp: App {
    @State private var store: JobStore

    init() {
        let store: JobStore
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let isReadmeCapture = environment["LAUNCHD_TOC_README_CAPTURE"] == "1"
            || arguments.contains("-READMECapture")
        let isUITesting = environment["LAUNCHD_TOC_UI_TESTING"] == "1"
            || arguments.contains("-UITesting")
        if isReadmeCapture || isUITesting {
            let suiteName = isReadmeCapture
                ? "com.litsquare.launchdtoc.readme-capture"
                : "com.litsquare.launchdtoc.ui-testing"
            store = Self.syntheticStore(defaultsSuiteName: suiteName)
        } else {
            store = JobStore()
        }
        #else
        store = JobStore()
        #endif

        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(store: store)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(isReadmeCapture ? .light : nil)
                .onAppear {
                    store.setRunningJobCountObserver { runningJobCount in
                        DockTileBadgeController().update(runningJobCount: runningJobCount)
                    }
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            LaunchdTOCCommands(store: store)
        }

        Settings {
            SettingsView(store: store)
                .frame(width: 520)
        }
    }

    private var isReadmeCapture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["LAUNCHD_TOC_README_CAPTURE"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-READMECapture")
        #else
        false
        #endif
    }

    #if DEBUG
    private static func syntheticStore(defaultsSuiteName: String) -> JobStore {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let root = FileManager.default.temporaryDirectory.appending(
            path: "launchd-toc-synthetic",
            directoryHint: .isDirectory
        )
        let locations = LaunchdLocations(
            userAgents: root.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory),
            globalAgents: root.appending(path: "Library/GlobalAgents", directoryHint: .isDirectory),
            globalDaemons: root.appending(path: "Library/Daemons", directoryHint: .isDirectory),
            appleAgents: root.appending(path: "System/Agents", directoryHint: .isDirectory),
            appleDaemons: root.appending(path: "System/Daemons", directoryHint: .isDirectory),
            applicationSupport: root.appending(path: "Application Support", directoryHint: .isDirectory)
        )

        return JobStore(
            repository: PlistRepository(locations: locations),
            launchctl: SyntheticLaunchctl(),
            defaults: defaults,
            initialJobs: demoJobs,
            inventoryRefreshEnabled: false
        )
    }

    private static var demoJobs: [LaunchdJob] {
        let photoBackupConfiguration = JobConfiguration(
            label: "com.example.backup.photos",
            programArguments: [
                "/usr/bin/python3",
                "/Users/demo/Applications/Photo Backup/photo_backup.py",
                "sync",
                "--library",
                "/Users/demo/Pictures"
            ],
            runAtLoad: true,
            keepAlive: true,
            throttleInterval: 10,
            processType: .background,
            workingDirectory: "/Users/demo/Documents/Photo Backup",
            environment: [
                "BACKUP_PROFILE": "demo",
                "LOG_LEVEL": "info"
            ],
            standardOutPath: "/Users/demo/Library/Logs/Photo Backup/backup.log",
            standardErrorPath: "/Users/demo/Library/Logs/Photo Backup/backup-error.log"
        )
        let photoBackup = LaunchdJob(
            plistURL: demoPlistURL(
                label: photoBackupConfiguration.label,
                source: .userAgent
            ),
            source: .userAgent,
            configuration: photoBackupConfiguration,
            runtimeState: .running(pid: 4_242),
            scheduleSummary: "At load",
            lastRun: Date(timeIntervalSince1970: 1_785_241_800)
        )

        let dailyReportConfiguration = JobConfiguration(
            label: "com.example.reports.daily",
            program: "/usr/bin/shortcuts",
            programArguments: [
                "/usr/bin/shortcuts",
                "run",
                "Create Daily Report"
            ],
            runAtLoad: false,
            keepAlive: false,
            startInterval: 86_400,
            workingDirectory: "/Users/demo/Documents/Reports",
            standardOutPath: "/Users/demo/Library/Logs/Daily Report/report.log"
        )
        let dailyReport = LaunchdJob(
            plistURL: demoPlistURL(
                label: dailyReportConfiguration.label,
                source: .userAgent
            ),
            source: .userAgent,
            configuration: dailyReportConfiguration,
            runtimeState: .waiting,
            scheduleSummary: "Every day",
            lastRun: Date(timeIntervalSince1970: 1_785_236_400)
        )

        let cleanupConfiguration = JobConfiguration(
            label: "com.example.downloads.cleanup",
            program: "/bin/zsh",
            programArguments: [
                "/bin/zsh",
                "/Users/demo/Scripts/cleanup-downloads.sh"
            ],
            keepAlive: false,
            startInterval: 3_600,
            workingDirectory: "/Users/demo/Downloads"
        )
        let cleanup = LaunchdJob(
            plistURL: demoPlistURL(
                label: cleanupConfiguration.label,
                source: .userAgent
            ),
            source: .userAgent,
            configuration: cleanupConfiguration,
            runtimeState: .disabled,
            scheduleSummary: "Every hour",
            lastRun: Date(timeIntervalSince1970: 1_785_232_800)
        )

        let menuHelperConfiguration = JobConfiguration(
            label: "com.example.menu.weather",
            program: "/Applications/Example Weather.app/Contents/MacOS/Example Weather",
            runAtLoad: true,
            keepAlive: false
        )
        let menuHelper = LaunchdJob(
            plistURL: demoPlistURL(
                label: menuHelperConfiguration.label,
                source: .globalAgent
            ),
            source: .globalAgent,
            configuration: menuHelperConfiguration,
            runtimeState: .unloaded,
            scheduleSummary: "At load"
        )

        let digestConfiguration = JobConfiguration(
            label: "com.example.notifications.digest",
            program: "/usr/bin/shortcuts",
            programArguments: [
                "/usr/bin/shortcuts",
                "run",
                "Send Weekly Digest"
            ],
            calendarSchedules: [
                CalendarSchedule(minute: 0, hour: 9, weekday: 1)
            ]
        )
        let digest = LaunchdJob(
            plistURL: demoPlistURL(
                label: digestConfiguration.label,
                source: .globalAgent
            ),
            source: .globalAgent,
            configuration: digestConfiguration,
            runtimeState: .waiting,
            scheduleSummary: "Monday at 09:00",
            lastRun: Date(timeIntervalSince1970: 1_784_731_600)
        )

        let maintenanceConfiguration = JobConfiguration(
            label: "com.example.cache.maintenance",
            program: "/usr/local/bin/example-maintenance",
            keepAlive: false,
            processType: .background
        )
        let maintenance = LaunchdJob(
            plistURL: demoPlistURL(
                label: maintenanceConfiguration.label,
                source: .daemon
            ),
            source: .daemon,
            configuration: maintenanceConfiguration,
            runtimeState: .failed(exitCode: 1),
            scheduleSummary: "Not scheduled",
            lastRun: Date(timeIntervalSince1970: 1_785_239_100)
        )

        let searchIndexConfiguration = JobConfiguration(
            label: "com.example.search.index",
            program: "/usr/local/bin/example-indexer",
            runAtLoad: true,
            keepAlive: true,
            throttleInterval: 30,
            processType: .adaptive
        )
        let searchIndex = LaunchdJob(
            plistURL: demoPlistURL(
                label: searchIndexConfiguration.label,
                source: .daemon
            ),
            source: .daemon,
            configuration: searchIndexConfiguration,
            runtimeState: .running(pid: 8_120),
            scheduleSummary: "At load",
            lastRun: Date(timeIntervalSince1970: 1_785_241_200)
        )

        return [
            photoBackup,
            dailyReport,
            cleanup,
            menuHelper,
            digest,
            maintenance,
            searchIndex
        ]
    }

    private static func demoPlistURL(label: String, source: JobSource) -> URL {
        switch source {
        case .userAgent:
            URL(filePath: "/Users/demo/Library/LaunchAgents/\(label).plist")
        case .globalAgent:
            URL(filePath: "/Library/LaunchAgents/\(label).plist")
        case .daemon:
            URL(filePath: "/Library/LaunchDaemons/\(label).plist")
        case .appleAgent:
            URL(filePath: "/System/Library/LaunchAgents/\(label).plist")
        case .appleDaemon:
            URL(filePath: "/System/Library/LaunchDaemons/\(label).plist")
        }
    }
    #endif
}

#if DEBUG
private actor SyntheticLaunchctl: LaunchctlRunning {
    func runtimeState(for job: LaunchdJob) async -> JobRuntimeState {
        job.runtimeState
    }

    func disabledLabels(in domain: String) async -> Set<String> {
        []
    }

    func perform(_ action: LaunchctlAction, on job: LaunchdJob) async throws {}
}
#endif

@MainActor
private struct LaunchdTOCCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let store: JobStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Launchd TOC") {
                store.showsAbout = true
            }
        }

        CommandGroup(replacing: .newItem) {
            #if DEBUG
            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()
            #endif

            Button("New Agent…") {
                store.presentNewAgent()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Job") {
            Button("Load or Unload") {
                store.loadOrUnloadSelected()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Run Now") {
                store.runSelected()
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Restart") {
                store.restartSelected()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Divider()

            Button("Edit…") {
                store.presentEditor()
            }
            .keyboardShortcut("e", modifiers: .command)

            Divider()

            Button("Disable") {
                store.requestDisable()
            }

            Button("Move to Trash…", role: .destructive) {
                store.requestTrash()
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandGroup(after: .help) {
            Button("Check for Updates…") {
                Task { await store.checkForUpdates() }
            }
        }
    }
}
