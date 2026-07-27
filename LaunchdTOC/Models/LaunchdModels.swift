import Foundation

enum JobSource: String, CaseIterable, Codable, Hashable, Sendable {
    case userAgent
    case globalAgent
    case daemon
    case appleAgent
    case appleDaemon

    var displayName: String {
        switch self {
        case .userAgent: "User Agent"
        case .globalAgent: "Global Agent"
        case .daemon: "Daemon"
        case .appleAgent: "Apple Agent"
        case .appleDaemon: "Apple Daemon"
        }
    }

    var isEditable: Bool { self == .userAgent }
    var isAgent: Bool { self != .daemon && self != .appleDaemon }

    func domain(userID: uid_t = getuid()) -> String {
        isAgent ? "gui/\(userID)" : "system"
    }
}

enum JobRuntimeState: Hashable, Sendable {
    case disabled
    case unloaded
    case waiting
    case running(pid: Int32)
    case failed(exitCode: Int32)
    case unknown

    var label: String {
        switch self {
        case .disabled: "Disabled"
        case .unloaded: "Unloaded"
        case .waiting: "Loaded"
        case .running: "Running"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .disabled, .unloaded: "pause.circle"
        case .waiting: "clock"
        case .running: "play.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var pid: Int32? {
        guard case let .running(pid) = self else { return nil }
        return pid
    }

    var sortValue: String {
        switch self {
        case .running: "0-running"
        case .waiting: "1-waiting"
        case .failed: "2-failed"
        case .disabled: "3-disabled"
        case .unloaded: "4-unloaded"
        case .unknown: "5-unknown"
        }
    }
}

enum PlistFormat: String, Codable, Hashable, Sendable {
    case xml
    case binary

    init(_ format: PropertyListSerialization.PropertyListFormat) {
        self = format == .binary ? .binary : .xml
    }

    var foundationValue: PropertyListSerialization.PropertyListFormat {
        self == .binary ? .binary : .xml
    }
}

indirect enum PropertyListValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case date(Date)
    case data(Data)
    case array([PropertyListValue])
    case dictionary([String: PropertyListValue])

    init?(foundationValue value: Any) {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .boolean(value)
        case let value as Int:
            self = .integer(value)
        case let value as NSNumber:
            self = .real(value.doubleValue)
        case let value as Date:
            self = .date(value)
        case let value as Data:
            self = .data(value)
        case let value as [Any]:
            let converted = value.compactMap(PropertyListValue.init(foundationValue:))
            guard converted.count == value.count else { return nil }
            self = .array(converted)
        case let value as [String: Any]:
            var converted: [String: PropertyListValue] = [:]
            for (key, child) in value {
                guard let childValue = PropertyListValue(foundationValue: child) else { return nil }
                converted[key] = childValue
            }
            self = .dictionary(converted)
        default:
            return nil
        }
    }

    var foundationValue: Any {
        switch self {
        case let .string(value): value
        case let .integer(value): value
        case let .real(value): value
        case let .boolean(value): value
        case let .date(value): value
        case let .data(value): value
        case let .array(value): value.map(\.foundationValue)
        case let .dictionary(value): value.mapValues(\.foundationValue)
        }
    }

    var displayString: String {
        switch self {
        case let .string(value): "\"\(value)\""
        case let .integer(value): String(value)
        case let .real(value): String(value)
        case let .boolean(value): value ? "true" : "false"
        case let .date(value): value.formatted(date: .abbreviated, time: .standard)
        case let .data(value): "<\(value.count) bytes>"
        case let .array(value):
            "[\(value.map(\.displayString).joined(separator: ", "))]"
        case let .dictionary(value):
            "{ \(value.keys.sorted().map { "\($0): \(value[$0]?.displayString ?? "")" }.joined(separator: ", ")) }"
        }
    }
}

struct CalendarSchedule: Hashable, Identifiable, Sendable {
    var id = UUID()
    var minute: Int?
    var hour: Int?
    var day: Int?
    var weekday: Int?
    var month: Int?
    var rawValues: [String: PropertyListValue] = [:]

    init(
        id: UUID = UUID(),
        minute: Int? = nil,
        hour: Int? = nil,
        day: Int? = nil,
        weekday: Int? = nil,
        month: Int? = nil,
        rawValues: [String: PropertyListValue] = [:]
    ) {
        self.id = id
        self.minute = minute
        self.hour = hour
        self.day = day
        self.weekday = weekday
        self.month = month
        self.rawValues = rawValues
    }

    init(dictionary: [String: PropertyListValue]) {
        rawValues = dictionary
        minute = dictionary["Minute"]?.integerValue
        hour = dictionary["Hour"]?.integerValue
        day = dictionary["Day"]?.integerValue
        weekday = dictionary["Weekday"]?.integerValue
        month = dictionary["Month"]?.integerValue
    }

    var propertyListValue: PropertyListValue {
        var values = rawValues
        values.setInteger(minute, forKey: "Minute")
        values.setInteger(hour, forKey: "Hour")
        values.setInteger(day, forKey: "Day")
        values.setInteger(weekday, forKey: "Weekday")
        values.setInteger(month, forKey: "Month")
        return .dictionary(values)
    }
}

extension PropertyListValue {
    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case let .integer(value) = self else { return nil }
        return value
    }

    var booleanValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    var dictionaryValue: [String: PropertyListValue]? {
        guard case let .dictionary(value) = self else { return nil }
        return value
    }

    var arrayValue: [PropertyListValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }
}

private extension Dictionary where Key == String, Value == PropertyListValue {
    mutating func setInteger(_ value: Int?, forKey key: String) {
        if let value {
            self[key] = .integer(value)
        } else {
            removeValue(forKey: key)
        }
    }
}

struct JobConfiguration: Hashable, Sendable {
    static let supportedKeys: Set<String> = [
        "Label", "Program", "ProgramArguments", "RunAtLoad", "KeepAlive",
        "StartInterval", "StartCalendarInterval", "WorkingDirectory",
        "EnvironmentVariables", "StandardOutPath", "StandardErrorPath"
    ]

    var label: String
    var program: String?
    var programArguments: [String]
    var runAtLoad: Bool
    var keepAlive: Bool?
    var startInterval: Int?
    var calendarSchedules: [CalendarSchedule]
    var workingDirectory: String?
    var environment: [String: String]
    var standardOutPath: String?
    var standardErrorPath: String?
    var rawValues: [String: PropertyListValue]
    var originalFormat: PlistFormat
    var calendarWasArray: Bool

    init(
        label: String,
        program: String? = nil,
        programArguments: [String] = [],
        runAtLoad: Bool = false,
        keepAlive: Bool? = false,
        startInterval: Int? = nil,
        calendarSchedules: [CalendarSchedule] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
        rawValues: [String: PropertyListValue] = [:],
        originalFormat: PlistFormat = .xml,
        calendarWasArray: Bool = false
    ) {
        self.label = label
        self.program = program
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.startInterval = startInterval
        self.calendarSchedules = calendarSchedules
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.rawValues = rawValues
        self.originalFormat = originalFormat
        self.calendarWasArray = calendarWasArray
    }

    init(
        propertyList: [String: PropertyListValue],
        format: PlistFormat,
        fallbackLabel: String
    ) {
        rawValues = propertyList
        originalFormat = format
        label = propertyList["Label"]?.stringValue ?? fallbackLabel
        program = propertyList["Program"]?.stringValue
        programArguments = propertyList["ProgramArguments"]?.arrayValue?.compactMap(\.stringValue) ?? []
        runAtLoad = propertyList["RunAtLoad"]?.booleanValue ?? false

        if let keepAliveValue = propertyList["KeepAlive"]?.booleanValue {
            keepAlive = keepAliveValue
        } else if propertyList["KeepAlive"] == nil {
            keepAlive = false
        } else {
            keepAlive = nil
        }

        startInterval = propertyList["StartInterval"]?.integerValue
        if let calendarArray = propertyList["StartCalendarInterval"]?.arrayValue {
            calendarWasArray = true
            calendarSchedules = calendarArray.compactMap(\.dictionaryValue).map(CalendarSchedule.init)
        } else if let calendar = propertyList["StartCalendarInterval"]?.dictionaryValue {
            calendarWasArray = false
            calendarSchedules = [CalendarSchedule(dictionary: calendar)]
        } else {
            calendarWasArray = false
            calendarSchedules = []
        }

        workingDirectory = propertyList["WorkingDirectory"]?.stringValue
        environment = propertyList["EnvironmentVariables"]?.dictionaryValue?
            .compactMapValues(\.stringValue) ?? [:]
        standardOutPath = propertyList["StandardOutPath"]?.stringValue
        standardErrorPath = propertyList["StandardErrorPath"]?.stringValue
    }

    var executable: String? {
        program ?? programArguments.first
    }

    var advancedValues: [String: PropertyListValue] {
        var values = rawValues.filter { !Self.supportedKeys.contains($0.key) }
        if keepAlive == nil, let rawKeepAlive = rawValues["KeepAlive"] {
            values["KeepAlive"] = rawKeepAlive
        }
        if let rawEnvironment = rawValues["EnvironmentVariables"]?.dictionaryValue {
            let advancedEnvironment = rawEnvironment.filter { $0.value.stringValue == nil }
            if !advancedEnvironment.isEmpty {
                values["EnvironmentVariables"] = .dictionary(advancedEnvironment)
            }
        }
        return values
    }

    var serializedValues: [String: PropertyListValue] {
        var values = rawValues
        values["Label"] = .string(label)
        values.setOptionalString(program, forKey: "Program")
        values.setStringArray(programArguments, forKey: "ProgramArguments")
        values["RunAtLoad"] = .boolean(runAtLoad)

        if let keepAlive {
            values["KeepAlive"] = .boolean(keepAlive)
        }
        values.setOptionalInteger(startInterval, forKey: "StartInterval")

        if calendarSchedules.isEmpty {
            values.removeValue(forKey: "StartCalendarInterval")
        } else if calendarSchedules.count == 1, !calendarWasArray {
            values["StartCalendarInterval"] = calendarSchedules[0].propertyListValue
        } else {
            values["StartCalendarInterval"] = .array(calendarSchedules.map(\.propertyListValue))
        }

        values.setOptionalString(workingDirectory, forKey: "WorkingDirectory")
        var mergedEnvironment = rawValues["EnvironmentVariables"]?.dictionaryValue?
            .filter { $0.value.stringValue == nil } ?? [:]
        for (key, value) in environment {
            mergedEnvironment[key] = .string(value)
        }
        if mergedEnvironment.isEmpty {
            values.removeValue(forKey: "EnvironmentVariables")
        } else {
            values["EnvironmentVariables"] = .dictionary(mergedEnvironment)
        }
        values.setOptionalString(standardOutPath, forKey: "StandardOutPath")
        values.setOptionalString(standardErrorPath, forKey: "StandardErrorPath")
        return values
    }
}

private extension Dictionary where Key == String, Value == PropertyListValue {
    mutating func setOptionalString(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            self[key] = .string(value)
        } else {
            removeValue(forKey: key)
        }
    }

    mutating func setOptionalInteger(_ value: Int?, forKey key: String) {
        if let value {
            self[key] = .integer(value)
        } else {
            removeValue(forKey: key)
        }
    }

    mutating func setStringArray(_ values: [String], forKey key: String) {
        if values.isEmpty {
            removeValue(forKey: key)
        } else {
            self[key] = .array(values.map(PropertyListValue.string))
        }
    }
}

struct LaunchdJob: Identifiable, Hashable, Sendable {
    let id: String
    var label: String
    let plistURL: URL
    let source: JobSource
    var configuration: JobConfiguration
    var runtimeState: JobRuntimeState
    var scheduleSummary: String
    var predictedRuns: [Date]
    var lastRun: Date?
    var parseIssue: String?

    init(
        plistURL: URL,
        source: JobSource,
        configuration: JobConfiguration,
        runtimeState: JobRuntimeState = .unknown,
        scheduleSummary: String = "Not scheduled",
        predictedRuns: [Date] = [],
        lastRun: Date? = nil,
        parseIssue: String? = nil
    ) {
        id = "\(source.rawValue):\(plistURL.standardizedFileURL.path)"
        label = configuration.label
        self.plistURL = plistURL
        self.source = source
        self.configuration = configuration
        self.runtimeState = runtimeState
        self.scheduleSummary = scheduleSummary
        self.predictedRuns = predictedRuns
        self.lastRun = lastRun
        self.parseIssue = parseIssue
    }

    var stateSortValue: String { runtimeState.sortValue }
    var lastRunText: String {
        lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }
    var pidText: String {
        runtimeState.pid.map(String.init) ?? "—"
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case userAgents
    case globalAgents
    case daemons
    case running
    case attention
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Jobs"
        case .userAgents: "User Agents"
        case .globalAgents: "Global Agents"
        case .daemons: "Daemons"
        case .running: "Running"
        case .attention: "Needs Attention"
        case .disabled: "Disabled"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "list.bullet.rectangle"
        case .userAgents: "person.crop.circle"
        case .globalAgents: "person.2.circle"
        case .daemons: "gearshape.2"
        case .running: "play.circle.fill"
        case .attention: "exclamationmark.triangle"
        case .disabled: "pause.circle"
        }
    }
}
