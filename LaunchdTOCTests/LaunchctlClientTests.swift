import Foundation
import Testing
@testable import Launchd_TOC

@Suite("launchctl client")
struct LaunchctlClientTests {
    private func job(source: JobSource = .userAgent) -> LaunchdJob {
        LaunchdJob(
            plistURL: URL(filePath: "/Users/test/Library/LaunchAgents/com.litsquare.test.plist"),
            source: source,
            configuration: JobConfiguration(
                label: "com.litsquare.test",
                program: "/usr/bin/true"
            )
        )
    }

    @Test("Every action uses the fixed executable and exact argument array")
    func exactArguments() async throws {
        let runner = StubCommandRunner()
        let client = LaunchctlClient(commandRunner: runner, userID: 501)
        let userJob = job()

        try await client.perform(.load, on: userJob)
        try await client.perform(.unload, on: userJob)
        try await client.perform(.run, on: userJob)
        try await client.perform(.restart, on: userJob)
        try await client.perform(.enable, on: userJob)
        try await client.perform(.disable, on: userJob)

        let calls = await runner.invocations()
        #expect(calls.allSatisfy { $0.executableURL == URL(filePath: "/bin/launchctl") })
        #expect(calls.map(\.arguments) == [
            ["bootstrap", "gui/501", userJob.plistURL.path],
            ["bootout", "gui/501/com.litsquare.test"],
            ["kickstart", "-p", "gui/501/com.litsquare.test"],
            ["kickstart", "-kp", "gui/501/com.litsquare.test"],
            ["enable", "gui/501/com.litsquare.test"],
            ["disable", "gui/501/com.litsquare.test"]
        ])
        #expect(client.serviceTarget(for: job(source: .daemon)) == "system/com.litsquare.test")
    }

    @Test(
        "Runtime parser handles running, waiting, failed, unloaded, and unknown",
        arguments: [
            (
                CommandResult(
                    executableURL: LaunchctlClient.executableURL,
                    arguments: [],
                    standardOutput: """
                    gui/501/com.litsquare.test = {
                        state = running
                        pid = 987
                        resource coalition = {
                            state = active
                        }
                    }
                    """,
                    standardError: "",
                    exitCode: 0
                ),
                JobRuntimeState.running(pid: 987)
            ),
            (
                CommandResult(
                    executableURL: LaunchctlClient.executableURL,
                    arguments: [],
                    standardOutput: "state = waiting\nlast exit code = 0",
                    standardError: "",
                    exitCode: 0
                ),
                JobRuntimeState.waiting
            ),
            (
                CommandResult(
                    executableURL: LaunchctlClient.executableURL,
                    arguments: [],
                    standardOutput: "state = exited\nlast exit code = 7",
                    standardError: "",
                    exitCode: 0
                ),
                JobRuntimeState.failed(exitCode: 7)
            ),
            (
                CommandResult(
                    executableURL: LaunchctlClient.executableURL,
                    arguments: [],
                    standardOutput: "",
                    standardError: "Could not find service",
                    exitCode: 113
                ),
                JobRuntimeState.unloaded
            ),
            (
                CommandResult(
                    executableURL: LaunchctlClient.executableURL,
                    arguments: [],
                    standardOutput: "future format",
                    standardError: "",
                    exitCode: 0
                ),
                JobRuntimeState.unknown
            )
        ]
    )
    func runtimeParsing(result: CommandResult, expected: JobRuntimeState) {
        #expect(LaunchctlClient.parseRuntimeState(result) == expected)
    }

    @Test("Disabled parser accepts only true overrides")
    func disabledParsing() {
        let output = """
        disabled services = {
            "com.litsquare.disabled" => true
            "com.litsquare.enabled" => false
        }
        """
        #expect(LaunchctlClient.parseDisabledLabels(output) == ["com.litsquare.disabled"])
    }

    @Test("Unexpected executables are refused")
    func commandAllowlist() async {
        let runner = SystemCommandRunner()
        await #expect(throws: CommandExecutionError.self) {
            try await runner.run(
                executableURL: URL(filePath: "/bin/sh"),
                arguments: ["-c", "echo unsafe"]
            )
        }
    }
}
