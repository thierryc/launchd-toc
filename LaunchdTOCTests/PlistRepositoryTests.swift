import Foundation
import Testing
@testable import Launchd_TOC

@Suite("Property list repository")
struct PlistRepositoryTests {
    @Test("XML round trips preserve nested unknown values and advanced KeepAlive")
    func xmlRoundTripPreservesUnknownValues() async throws {
        let temporary = try TemporaryRepository(testName: "xml")
        defer { temporary.remove() }
        let destination = temporary.locations.userAgents.appending(path: "fixture.plist")
        try FileManager.default.copyItem(at: fixtureURL("valid.xml"), to: destination)

        var configuration = try temporary.repository.loadConfiguration(at: destination)
        #expect(configuration.originalFormat == .xml)
        #expect(configuration.keepAlive == nil)
        #expect(configuration.calendarSchedules.count == 2)
        #expect(configuration.executable == "/Users/example/工具/run")
        configuration.runAtLoad = true
        configuration.calendarSchedules[0].minute = 30

        try await temporary.repository.save(configuration, to: destination)
        let reloaded = try temporary.repository.loadConfiguration(at: destination)
        #expect(reloaded.originalFormat == .xml)
        #expect(reloaded.keepAlive == nil)
        #expect(reloaded.rawValues["VendorConfiguration"] == configuration.rawValues["VendorConfiguration"])
        #expect(
            reloaded.rawValues["EnvironmentVariables"]?.dictionaryValue?["VendorNestedValue"]
                == configuration.rawValues["EnvironmentVariables"]?.dictionaryValue?["VendorNestedValue"]
        )
        #expect(
            reloaded.calendarSchedules[0].rawValues["VendorNestedValue"]
                == configuration.calendarSchedules[0].rawValues["VendorNestedValue"]
        )
        #expect(reloaded.runAtLoad)
        #expect(reloaded.calendarSchedules[0].minute == 30)
    }

    @Test("Binary property lists retain binary format")
    func binaryRoundTripPreservesFormat() async throws {
        let temporary = try TemporaryRepository(testName: "binary")
        defer { temporary.remove() }
        let destination = temporary.locations.userAgents.appending(path: "binary.plist")
        let values: [String: Any] = [
            "Label": "com.litsquare.binary",
            "Program": "/usr/bin/true",
            "Unknown": ["Nested": ["α", "β"]]
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .binary,
            options: 0
        )
        try data.write(to: destination)

        var configuration = try temporary.repository.loadConfiguration(at: destination)
        #expect(configuration.originalFormat == .binary)
        configuration.runAtLoad = true
        try await temporary.repository.save(configuration, to: destination)

        let saved = try Data(contentsOf: destination)
        var format = PropertyListSerialization.PropertyListFormat.xml
        _ = try PropertyListSerialization.propertyList(from: saved, format: &format)
        #expect(format == .binary)
        let reloaded = try temporary.repository.loadConfiguration(at: destination)
        #expect(reloaded.rawValues["Unknown"] == configuration.rawValues["Unknown"])
    }

    @Test("Malformed files remain visible with a parse issue")
    func malformedFilesAppearInInventory() throws {
        let temporary = try TemporaryRepository(testName: "malformed")
        defer { temporary.remove() }
        let destination = temporary.locations.userAgents.appending(path: "malformed.plist")
        try FileManager.default.copyItem(at: fixtureURL("malformed"), to: destination)

        let jobs = temporary.repository.scan(showAppleServices: false)
        #expect(jobs.count == 1)
        #expect(jobs[0].parseIssue != nil)
        #expect(jobs[0].runtimeState == .unknown)
    }

    @Test("Duplicate labels from separate sources keep distinct identities")
    func duplicateLabelsHaveDistinctIDs() throws {
        let temporary = try TemporaryRepository(testName: "duplicates")
        defer { temporary.remove() }
        let object: [String: Any] = [
            "Label": "com.litsquare.duplicate",
            "Program": "/usr/bin/true"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: object,
            format: .xml,
            options: 0
        )
        try data.write(to: temporary.locations.userAgents.appending(path: "one.plist"))
        try data.write(to: temporary.locations.globalAgents.appending(path: "two.plist"))

        let jobs = temporary.repository.scan(showAppleServices: false)
        #expect(jobs.count == 2)
        #expect(Set(jobs.map(\.id)).count == 2)
        #expect(Set(jobs.map(\.label)) == ["com.litsquare.duplicate"])
    }

    @Test("Apple services are omitted unless explicitly enabled")
    func appleServicesRequireSetting() throws {
        let temporary = try TemporaryRepository(testName: "apple")
        defer { temporary.remove() }
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "com.apple.fixture", "Program": "/usr/bin/true"],
            format: .xml,
            options: 0
        )
        try data.write(to: temporary.locations.appleAgents.appending(path: "apple.plist"))
        #expect(temporary.repository.scan(showAppleServices: false).isEmpty)
        #expect(temporary.repository.scan(showAppleServices: true).count == 1)
    }

    @Test("Security boundary rejects traversal, system paths, symlinks, and unsafe labels")
    func pathConfinement() throws {
        let temporary = try TemporaryRepository(testName: "security")
        defer { temporary.remove() }

        let traversal = temporary.locations.userAgents.appending(path: "../escape.plist")
        #expect(throws: PlistRepositoryError.self) {
            try temporary.repository.validatedUserAgentURL(traversal, allowMissing: true)
        }
        #expect(throws: PlistRepositoryError.self) {
            try temporary.repository.validatedUserAgentURL(
                temporary.locations.globalAgents.appending(path: "global.plist"),
                allowMissing: true
            )
        }
        #expect(!PlistRepository.isValidLabel("com.example;rm"))
        #expect(!PlistRepository.isValidLabel("../example"))
        #expect(!PlistRepository.isValidLabel("$(touch bad)"))

        let outside = temporary.root.appending(path: "outside.plist")
        try Data().write(to: outside)
        let symlink = temporary.locations.userAgents.appending(path: "linked.plist")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        #expect(throws: PlistRepositoryError.self) {
            try temporary.repository.validatedUserAgentURL(symlink, allowMissing: false)
        }
    }

    @Test("Validation rejects missing executables and invalid schedule values")
    func structuredValidation() async throws {
        let temporary = try TemporaryRepository(testName: "validation")
        defer { temporary.remove() }
        await #expect(throws: PlistRepositoryError.self) {
            try await temporary.repository.validate(JobConfiguration(label: "com.litsquare.empty"))
        }
        await #expect(throws: PlistRepositoryError.self) {
            try await temporary.repository.validate(
                JobConfiguration(
                    label: "com.litsquare.interval",
                    program: "/usr/bin/true",
                    startInterval: 0
                )
            )
        }
        await #expect(throws: PlistRepositoryError.self) {
            try await temporary.repository.validate(
                JobConfiguration(
                    label: "com.litsquare.calendar",
                    program: "/usr/bin/true",
                    calendarSchedules: [CalendarSchedule(hour: 30)]
                )
            )
        }
    }
}
