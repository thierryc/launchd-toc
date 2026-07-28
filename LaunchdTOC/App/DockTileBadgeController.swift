import AppKit

@MainActor
protocol DockTileBadgeDisplaying: AnyObject {
    var badgeLabel: String? { get set }
}

extension NSDockTile: DockTileBadgeDisplaying {}

@MainActor
struct DockTileBadgeController {
    private let dockTile: any DockTileBadgeDisplaying

    init(dockTile: any DockTileBadgeDisplaying = NSApplication.shared.dockTile) {
        self.dockTile = dockTile
    }

    func update(runningJobCount: Int) {
        dockTile.badgeLabel = Self.badgeLabel(for: runningJobCount)
    }

    private static func badgeLabel(for runningJobCount: Int) -> String? {
        guard runningJobCount > 0 else { return nil }
        return runningJobCount > 99 ? "99+" : String(runningJobCount)
    }
}
