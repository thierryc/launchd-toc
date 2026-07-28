import Foundation

enum LaunchDurationUnit: String, CaseIterable, Identifiable, Sendable {
    case seconds
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var multiplier: Int {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3_600
        case .days: 86_400
        }
    }

    var title: String {
        rawValue.capitalized
    }

    static func bestFit(seconds: Int) -> (amount: Int, unit: LaunchDurationUnit) {
        for unit in [LaunchDurationUnit.days, .hours, .minutes] {
            if seconds > 0, seconds.isMultiple(of: unit.multiplier) {
                return (seconds / unit.multiplier, unit)
            }
        }
        return (seconds, .seconds)
    }

    func seconds(for amount: Int) -> Int? {
        let result = amount.multipliedReportingOverflow(by: multiplier)
        return result.overflow ? nil : result.partialValue
    }
}

enum LaunchDurationFormatter {
    static func description(seconds: Int) -> String {
        let fit = LaunchDurationUnit.bestFit(seconds: seconds)
        let singular = fit.amount == 1
        let unit: String
        switch fit.unit {
        case .seconds: unit = singular ? "second" : "seconds"
        case .minutes: unit = singular ? "minute" : "minutes"
        case .hours: unit = singular ? "hour" : "hours"
        case .days: unit = singular ? "day" : "days"
        }
        return "\(fit.amount) \(unit)"
    }
}

extension JobConfiguration {
    var executableSourceDescription: String {
        program == nil ? "First ProgramArguments value" : "Program key"
    }

    var launchCommandTokens: [String] {
        guard let executable, !executable.isEmpty else { return [] }
        if program != nil {
            return [executable] + programArguments.dropFirst()
        }
        return programArguments
    }

    var commandArguments: [String] {
        Array(programArguments.dropFirst())
    }

    var commandPreview: String {
        launchCommandTokens.map(Self.quoteForDisplay).joined(separator: " ")
    }

    var launchBehaviorSummary: String {
        switch (runAtLoad, keepAlive) {
        case (_, true):
            "Starts when loaded, and launchd keeps it running."
        case (true, nil):
            "Starts when loaded and uses conditional keep-alive rules."
        case (false, nil):
            "Uses conditional keep-alive rules to decide when it should run."
        case (true, _):
            "Starts once when the job is loaded."
        case (false, _):
            if startInterval != nil || !calendarSchedules.isEmpty {
                "Starts when one of its launchd schedule triggers fires."
            } else {
                "Runs on demand or when you start it manually."
            }
        }
    }

    var repeatingScheduleDescription: String? {
        var parts: [String] = []
        if let startInterval {
            parts.append("Every \(LaunchDurationFormatter.description(seconds: startInterval))")
        }
        if calendarSchedules.count == 1 {
            parts.append("1 calendar trigger")
        } else if calendarSchedules.count > 1 {
            parts.append("\(calendarSchedules.count) calendar triggers")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var keepAliveDescription: String {
        switch keepAlive {
        case true: "Keeps running"
        case false: "Not kept running"
        case nil: "Conditional rules"
        }
    }

    private static func quoteForDisplay(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safeCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-"
        )
        if value.unicodeScalars.allSatisfy(safeCharacters.contains) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
