import Testing
@testable import Launchd_TOC

@Suite("Job presentation")
struct JobPresentationTests {
    @Test("ProgramArguments executable remains separate from command arguments")
    func inferredExecutableCommand() {
        let configuration = JobConfiguration(
            label: "com.litsquare.echo.automations",
            programArguments: [
                "/usr/local/bin/node",
                "/tmp/heartbeat script.js",
                "start",
                "--pid-file",
                "/tmp/heartbeat.pid"
            ],
            runAtLoad: true,
            keepAlive: true,
            throttleInterval: 10,
            processType: .background
        )

        #expect(configuration.executable == "/usr/local/bin/node")
        #expect(configuration.executableSourceDescription == "First ProgramArguments value")
        #expect(
            configuration.commandArguments
                == ["/tmp/heartbeat script.js", "start", "--pid-file", "/tmp/heartbeat.pid"]
        )
        #expect(
            configuration.commandPreview
                == "/usr/local/bin/node '/tmp/heartbeat script.js' start --pid-file /tmp/heartbeat.pid"
        )
        #expect(!configuration.commandPreview.contains("intervalMs"))
    }

    @Test("Program key preview excludes the explicit argv zero value")
    func programKeyCommand() {
        let configuration = JobConfiguration(
            label: "com.litsquare.program",
            program: "/usr/bin/tool",
            programArguments: ["custom-process-name", "--message", "it's ready"]
        )

        #expect(configuration.executableSourceDescription == "Program key")
        #expect(configuration.launchCommandTokens == ["/usr/bin/tool", "--message", "it's ready"])
        #expect(configuration.commandPreview == "/usr/bin/tool --message 'it'\\''s ready'")
    }

    @Test("Behavior summary distinguishes keep alive from repeating schedules")
    func behaviorSummary() {
        let continuous = JobConfiguration(
            label: "com.litsquare.continuous",
            program: "/usr/bin/true",
            runAtLoad: true,
            keepAlive: true,
            throttleInterval: 10
        )
        #expect(continuous.launchBehaviorSummary == "Starts when loaded, and launchd keeps it running.")
        #expect(continuous.repeatingScheduleDescription == nil)

        let scheduled = JobConfiguration(
            label: "com.litsquare.scheduled",
            program: "/usr/bin/true",
            startInterval: 120
        )
        #expect(scheduled.launchBehaviorSummary == "Starts when one of its launchd schedule triggers fires.")
        #expect(scheduled.repeatingScheduleDescription == "Every 2 minutes")
    }

    @Test("Duration editor selects readable exact units and detects overflow")
    func durations() {
        #expect(LaunchDurationUnit.bestFit(seconds: 120).amount == 2)
        #expect(LaunchDurationUnit.bestFit(seconds: 120).unit == .minutes)
        #expect(LaunchDurationFormatter.description(seconds: 86_400) == "1 day")
        #expect(LaunchDurationUnit.days.seconds(for: Int.max) == nil)
    }
}
