import Foundation
import Testing
@testable import Launchd_TOC

@Suite("Opt-in launchd integration")
struct IntegrationTests {
    @Test("Disposable user-agent lifecycle")
    func disposableLifecycle() async throws {
        guard ProcessInfo.processInfo.environment["LAUNCHD_TOC_RUN_INTEGRATION_TESTS"] == "1" else {
            return
        }

        let label = "com.litsquare.launchdtoc.tests.\(UUID().uuidString)"
        let configuration = JobConfiguration(
            label: label,
            program: "/usr/bin/true",
            runAtLoad: false,
            keepAlive: false
        )
        let repository = PlistRepository()
        let launchctl = LaunchctlClient()
        let url = try repository.newAgentURL(label: label)
        let job = LaunchdJob(
            plistURL: url,
            source: .userAgent,
            configuration: configuration
        )

        do {
            try await repository.save(configuration, to: url)
            try await launchctl.perform(.load, on: job)
            try await launchctl.perform(.run, on: job)
            try await launchctl.perform(.restart, on: job)
            try await launchctl.perform(.unload, on: job)
            _ = try repository.trash(url)
        } catch {
            try? await launchctl.perform(.unload, on: job)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
