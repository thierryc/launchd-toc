import Foundation

enum LaunchctlAction: Sendable {
    case load
    case unload
    case run
    case restart
    case enable
    case disable
}

protocol LaunchctlRunning: Sendable {
    func runtimeState(for job: LaunchdJob) async -> JobRuntimeState
    func disabledLabels(in domain: String) async -> Set<String>
    func perform(_ action: LaunchctlAction, on job: LaunchdJob) async throws
}

enum LaunchctlError: LocalizedError {
    case commandFailed(action: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(action, message):
            "\(action) failed: \(message)"
        }
    }
}

actor LaunchctlClient: LaunchctlRunning {
    static let executableURL = URL(filePath: "/bin/launchctl")

    private let commandRunner: any CommandExecuting
    private let userID: uid_t

    init(
        commandRunner: any CommandExecuting = SystemCommandRunner(),
        userID: uid_t = getuid()
    ) {
        self.commandRunner = commandRunner
        self.userID = userID
    }

    func runtimeState(for job: LaunchdJob) async -> JobRuntimeState {
        do {
            let result = try await commandRunner.run(
                executableURL: Self.executableURL,
                arguments: ["print", serviceTarget(for: job)]
            )
            return Self.parseRuntimeState(result)
        } catch {
            return .unknown
        }
    }

    func disabledLabels(in domain: String) async -> Set<String> {
        do {
            let result = try await commandRunner.run(
                executableURL: Self.executableURL,
                arguments: ["print-disabled", domain]
            )
            guard result.exitCode == 0 else { return [] }
            return Self.parseDisabledLabels(result.standardOutput)
        } catch {
            return []
        }
    }

    func perform(_ action: LaunchctlAction, on job: LaunchdJob) async throws {
        let arguments = arguments(for: action, job: job)
        let result = try await commandRunner.run(
            executableURL: Self.executableURL,
            arguments: arguments
        )
        guard result.exitCode == 0 else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw LaunchctlError.commandFailed(
                action: action.label,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    nonisolated func arguments(for action: LaunchctlAction, job: LaunchdJob) -> [String] {
        let domain = job.source.domain(userID: userID)
        let target = "\(domain)/\(job.label)"
        switch action {
        case .load:
            return ["bootstrap", domain, job.plistURL.path]
        case .unload:
            return ["bootout", target]
        case .run:
            return ["kickstart", "-p", target]
        case .restart:
            return ["kickstart", "-kp", target]
        case .enable:
            return ["enable", target]
        case .disable:
            return ["disable", target]
        }
    }

    nonisolated func serviceTarget(for job: LaunchdJob) -> String {
        "\(job.source.domain(userID: userID))/\(job.label)"
    }

    static func parseRuntimeState(_ result: CommandResult) -> JobRuntimeState {
        let combined = "\(result.standardOutput)\n\(result.standardError)"
        if result.exitCode != 0 {
            let lowercased = combined.lowercased()
            if lowercased.contains("could not find service")
                || lowercased.contains("service not found")
                || lowercased.contains("bad request")
            {
                return .unloaded
            }
            return .unknown
        }

        var state: String?
        var pid: Int32?
        var lastExitCode: Int32?
        var dictionaryDepth = result.standardOutput.contains(" = {") ? 0 : 1
        for rawLine in result.standardOutput.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if dictionaryDepth == 1 {
                if line.hasPrefix("state = ") {
                    state = String(line.dropFirst("state = ".count))
                } else if line.hasPrefix("pid = ") {
                    pid = Int32(line.dropFirst("pid = ".count))
                } else if line.hasPrefix("last exit code = ") {
                    lastExitCode = Int32(line.dropFirst("last exit code = ".count))
                }
            }
            dictionaryDepth += rawLine.filter { $0 == "{" }.count
            dictionaryDepth -= rawLine.filter { $0 == "}" }.count
        }

        if state == "running", let pid {
            return .running(pid: pid)
        }
        if let lastExitCode, lastExitCode != 0 {
            return .failed(exitCode: lastExitCode)
        }
        if state == "waiting" || state == "not running" || state == "exited" {
            return .waiting
        }
        return .unknown
    }

    static func parseDisabledLabels(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            guard line.contains("=> true") else { continue }
            guard
                let firstQuote = line.firstIndex(of: "\""),
                let secondQuote = line[line.index(after: firstQuote)...].firstIndex(of: "\"")
            else {
                continue
            }
            let label = String(line[line.index(after: firstQuote)..<secondQuote])
            labels.insert(label)
        }
        return labels
    }
}

private extension LaunchctlAction {
    var label: String {
        switch self {
        case .load: "Load"
        case .unload: "Unload"
        case .run: "Run Now"
        case .restart: "Restart"
        case .enable: "Enable"
        case .disable: "Disable"
        }
    }
}
