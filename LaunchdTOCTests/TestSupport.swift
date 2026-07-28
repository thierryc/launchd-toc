import Foundation
@testable import Launchd_TOC

actor StubCommandRunner: CommandExecuting {
    struct Invocation: Equatable, Sendable {
        let executableURL: URL
        let arguments: [String]
    }

    private var queuedResults: [CommandResult]
    private var recordedInvocations: [Invocation] = []

    init(results: [CommandResult] = []) {
        queuedResults = results
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        recordedInvocations.append(Invocation(executableURL: executableURL, arguments: arguments))
        if !queuedResults.isEmpty {
            return queuedResults.removeFirst()
        }
        return CommandResult(
            executableURL: executableURL,
            arguments: arguments,
            standardOutput: "",
            standardError: "",
            exitCode: 0
        )
    }

    func invocations() -> [Invocation] {
        recordedInvocations
    }
}

struct StubHTTPClient: HTTPFetching {
    let data: Data
    let statusCode: Int
    var failureCode: URLError.Code?

    func get(_ url: URL) async throws -> HTTPResponse {
        if let failureCode {
            throw URLError(failureCode)
        }
        return HTTPResponse(data: data, statusCode: statusCode)
    }
}

struct TemporaryRepository {
    let root: URL
    let locations: LaunchdLocations
    let repository: PlistRepository

    init(testName: String, commandRunner: any CommandExecuting = StubCommandRunner()) throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "LaunchdTOCTests-\(testName)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let user = root.appending(path: "用户/Library/LaunchAgents", directoryHint: .isDirectory)
        let global = root.appending(path: "Global/LaunchAgents", directoryHint: .isDirectory)
        let daemons = root.appending(path: "Global/LaunchDaemons", directoryHint: .isDirectory)
        let appleAgents = root.appending(path: "System/LaunchAgents", directoryHint: .isDirectory)
        let appleDaemons = root.appending(path: "System/LaunchDaemons", directoryHint: .isDirectory)
        let support = root.appending(path: "Application Support/Launchd TOC", directoryHint: .isDirectory)
        for directory in [user, global, daemons, appleAgents, appleDaemons, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        self.root = root
        locations = LaunchdLocations(
            userAgents: user,
            globalAgents: global,
            globalDaemons: daemons,
            appleAgents: appleAgents,
            appleDaemons: appleDaemons,
            applicationSupport: support
        )
        repository = PlistRepository(
            commandRunner: commandRunner,
            locations: locations
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

func fixtureURL(_ name: String) throws -> URL {
    let bundle = Bundle(for: FixtureToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return url
}

private final class FixtureToken {}
