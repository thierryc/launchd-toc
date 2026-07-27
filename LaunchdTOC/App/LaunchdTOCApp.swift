import SwiftUI

@main
struct LaunchdTOCApp: App {
    @State private var store: JobStore

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LAUNCHD_TOC_UI_TESTING"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-UITesting")
        {
            let defaults = UserDefaults(suiteName: "com.litsquare.launchdtoc.ui-testing")!
            defaults.removePersistentDomain(forName: "com.litsquare.launchdtoc.ui-testing")
            _store = State(
                initialValue: JobStore(
                    defaults: defaults,
                    initialJobs: Self.uiTestJobs
                )
            )
        } else {
            _store = State(initialValue: JobStore())
        }
        #else
        _store = State(initialValue: JobStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 980, minHeight: 640)
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

    #if DEBUG
    private static var uiTestJobs: [LaunchdJob] {
        let runningConfiguration = JobConfiguration(
            label: "com.litsquare.sample.running",
            program: "/usr/bin/true",
            runAtLoad: true,
            keepAlive: false,
            startInterval: 300,
            standardOutPath: "/tmp/launchd-toc-sample.log"
        )
        var running = LaunchdJob(
            plistURL: URL(filePath: "/tmp/com.litsquare.sample.running.plist"),
            source: .userAgent,
            configuration: runningConfiguration,
            runtimeState: .running(pid: 4_242),
            scheduleSummary: "Every 5 minutes"
        )
        running.predictedRuns = [
            Date(timeIntervalSince1970: 1_800_000_000),
            Date(timeIntervalSince1970: 1_800_000_300)
        ]

        let failingConfiguration = JobConfiguration(
            label: "com.litsquare.sample.attention",
            program: "/usr/bin/false",
            keepAlive: false
        )
        let failing = LaunchdJob(
            plistURL: URL(filePath: "/tmp/com.litsquare.sample.attention.plist"),
            source: .globalAgent,
            configuration: failingConfiguration,
            runtimeState: .failed(exitCode: 1),
            scheduleSummary: "Not scheduled"
        )
        return [running, failing]
    }
    #endif
}

@MainActor
private struct LaunchdTOCCommands: Commands {
    let store: JobStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Launchd TOC") {
                store.showsAbout = true
            }
        }

        CommandGroup(replacing: .newItem) {
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
