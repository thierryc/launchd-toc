import Foundation

struct CommandResult: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}

enum CommandExecutionError: LocalizedError, Equatable, Sendable {
    case executableNotAllowed(String)
    case failedToStart(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotAllowed(path):
            "Launchd TOC refused to run an unexpected executable: \(path)"
        case let .failedToStart(message):
            "The command could not start: \(message)"
        }
    }
}

protocol CommandExecuting: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult
}

struct SystemCommandRunner: CommandExecuting {
    private let allowedExecutablePaths: Set<String>

    init(
        allowedExecutablePaths: Set<String> = [
            "/bin/launchctl",
            "/usr/bin/plutil"
        ]
    ) {
        self.allowedExecutablePaths = allowedExecutablePaths
    }

    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        let allowlist = allowedExecutablePaths
        return try await Task.detached(priority: .userInitiated) {
            let path = executableURL.standardizedFileURL.path
            guard allowlist.contains(path) else {
                throw CommandExecutionError.executableNotAllowed(path)
            }

            let process = Process()
            let combinedOutput = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = combinedOutput
            process.standardError = combinedOutput

            do {
                try process.run()
            } catch {
                throw CommandExecutionError.failedToStart(error.localizedDescription)
            }

            // Drain while the process runs so verbose launchctl output cannot fill
            // a pipe buffer and deadlock. A combined stream is intentional:
            // callers treat all command text as diagnostic data.
            let outputData = combinedOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return CommandResult(
                executableURL: executableURL,
                arguments: arguments,
                standardOutput: String(decoding: outputData, as: UTF8.self),
                standardError: "",
                exitCode: process.terminationStatus
            )
        }.value
    }
}
