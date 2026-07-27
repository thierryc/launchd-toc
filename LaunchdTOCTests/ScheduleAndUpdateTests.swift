import Foundation
import Testing
@testable import Launchd_TOC

@Suite("Schedules and updates")
struct ScheduleAndUpdateTests {
    @Test("Interval schedules produce a concise summary and five runs")
    func intervalPreview() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let preview = SchedulePreview(
            calendar: Calendar(identifier: .gregorian),
            now: { start }
        )
        let configuration = JobConfiguration(
            label: "com.litsquare.interval",
            program: "/usr/bin/true",
            startInterval: 300
        )
        #expect(preview.summary(for: configuration) == "Every 5 minutes")
        let dates = preview.nextRuns(for: configuration)
        #expect(dates.count == 5)
        #expect(dates[0] == start.addingTimeInterval(300))
        #expect(dates[4] == start.addingTimeInterval(1_500))
    }

    @Test("Semantic versions compare stable numeric components")
    func semanticVersions() {
        #expect(SemanticVersion("v1.2.0")! > SemanticVersion("1.1.9")!)
        #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
        #expect(SemanticVersion("v2.0.0-beta.1")! > SemanticVersion("1.9.9")!)
        #expect(SemanticVersion("not-a-version") == nil)
    }

    @Test("Stable release offers the universal DMG")
    func stableUpdate() async throws {
        let data = Data(
            """
            {
              "tag_name": "v1.2.0",
              "name": "Launchd TOC 1.2",
              "body": "Notes",
              "html_url": "https://github.com/thierryc/launchd-toc/releases/tag/v1.2.0",
              "draft": false,
              "prerelease": false,
              "assets": [{
                "name": "Launchd-TOC-1.2.0-universal.dmg",
                "browser_download_url": "https://example.com/universal.dmg"
              }]
            }
            """.utf8
        )
        let checker = UpdateChecker(httpClient: StubHTTPClient(data: data, statusCode: 200))
        let result = try await checker.check(currentVersion: "1.0.0")
        guard case let .updateAvailable(release, downloadURL) = result else {
            Issue.record("Expected an update")
            return
        }
        #expect(release.tagName == "v1.2.0")
        #expect(downloadURL?.absoluteString == "https://example.com/universal.dmg")
    }

    @Test(
        "Update failures are nonblocking domain errors",
        arguments: [
            (403, UpdateCheckError.rateLimited),
            (429, UpdateCheckError.rateLimited),
            (500, UpdateCheckError.server(500))
        ]
    )
    func updateHTTPFailures(status: Int, expected: UpdateCheckError) async {
        let checker = UpdateChecker(httpClient: StubHTTPClient(data: Data(), statusCode: status))
        do {
            _ = try await checker.check(currentVersion: "1.0.0")
            Issue.record("Expected an error")
        } catch let error as UpdateCheckError {
            #expect(error.localizedDescription == expected.localizedDescription)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Prereleases and drafts are ignored")
    func prereleaseIsIgnored() async throws {
        let data = Data(
            """
            {
              "tag_name": "v2.0.0-beta.1",
              "name": null,
              "body": null,
              "html_url": "https://example.com/release",
              "draft": false,
              "prerelease": true,
              "assets": []
            }
            """.utf8
        )
        let checker = UpdateChecker(httpClient: StubHTTPClient(data: data, statusCode: 200))
        #expect(try await checker.check(currentVersion: "1.0.0") == .noRelease)
    }

    @Test("Malformed responses are reported")
    func malformedResponse() async {
        let checker = UpdateChecker(
            httpClient: StubHTTPClient(data: Data("{}".utf8), statusCode: 200)
        )
        await #expect(throws: UpdateCheckError.self) {
            try await checker.check(currentVersion: "1.0.0")
        }
    }

    @Test("Offline errors pass through without blocking state")
    func offline() async {
        let checker = UpdateChecker(
            httpClient: StubHTTPClient(
                data: Data(),
                statusCode: 0,
                failureCode: .notConnectedToInternet
            )
        )
        await #expect(throws: URLError.self) {
            try await checker.check(currentVersion: "1.0.0")
        }
    }
}
