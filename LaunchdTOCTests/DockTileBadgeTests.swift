import Foundation
import Testing
@testable import Launchd_TOC

@Suite("Dock tile badge")
@MainActor
struct DockTileBadgeTests {
    @Test("Running count includes every source and ignores current filters")
    func runningCount() {
        let suiteName = "com.litsquare.launchdtoc.tests.dock-tile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = JobStore(
            defaults: defaults,
            initialJobs: [
                job("user", source: .userAgent, state: .running(pid: 101)),
                job("global", source: .globalAgent, state: .running(pid: 102)),
                job("daemon", source: .daemon, state: .running(pid: 103)),
                job("apple", source: .appleAgent, state: .running(pid: 104)),
                job("waiting", source: .userAgent, state: .waiting),
                job("failed", source: .userAgent, state: .failed(exitCode: 1)),
                job("disabled", source: .userAgent, state: .disabled),
                job("unloaded", source: .userAgent, state: .unloaded),
                job("unknown", source: .userAgent, state: .unknown)
            ]
        )
        let dockTile = FakeDockTile()

        store.setRunningJobCountObserver { runningJobCount in
            DockTileBadgeController(dockTile: dockTile)
                .update(runningJobCount: runningJobCount)
        }

        #expect(store.runningJobCount == 4)
        #expect(dockTile.badgeLabel == "4")

        store.searchText = "no matching job"
        store.sidebarSelection = .disabled

        #expect(store.runningJobCount == 4)
        #expect(dockTile.badgeLabel == "4")
    }

    @Test("Badge hides zero, shows exact small counts, and caps large counts")
    func badgeFormatting() {
        let dockTile = FakeDockTile()
        let controller = DockTileBadgeController(dockTile: dockTile)

        dockTile.badgeLabel = "stale"
        controller.update(runningJobCount: 0)
        #expect(dockTile.badgeLabel == nil)

        controller.update(runningJobCount: 1)
        #expect(dockTile.badgeLabel == "1")

        controller.update(runningJobCount: 99)
        #expect(dockTile.badgeLabel == "99")

        controller.update(runningJobCount: 100)
        #expect(dockTile.badgeLabel == "99+")
    }

    @Test("Synthetic stores never replace fixtures with a live inventory scan")
    func syntheticInventoryIsolated() async {
        let suiteName = "com.litsquare.launchdtoc.tests.synthetic.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fixture = job("fixture", source: .userAgent, state: .running(pid: 101))
        let store = JobStore(
            defaults: defaults,
            initialJobs: [fixture],
            inventoryRefreshEnabled: false
        )

        await store.refresh()

        #expect(store.jobs == [fixture])
        #expect(store.isRefreshing == false)
    }

    private func job(
        _ suffix: String,
        source: JobSource,
        state: JobRuntimeState
    ) -> LaunchdJob {
        LaunchdJob(
            plistURL: URL(filePath: "/tmp/com.litsquare.dock-tile.\(suffix).plist"),
            source: source,
            configuration: JobConfiguration(
                label: "com.litsquare.dock-tile.\(suffix)",
                program: "/usr/bin/true"
            ),
            runtimeState: state
        )
    }
}

@MainActor
private final class FakeDockTile: DockTileBadgeDisplaying {
    var badgeLabel: String?
}
