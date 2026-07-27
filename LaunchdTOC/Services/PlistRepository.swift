import Foundation

struct LaunchdLocations: Sendable {
    let userAgents: URL
    let globalAgents: URL
    let globalDaemons: URL
    let appleAgents: URL
    let appleDaemons: URL
    let applicationSupport: URL

    static func live(fileManager: FileManager = .default) -> LaunchdLocations {
        let home = fileManager.homeDirectoryForCurrentUser
        let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? home.appending(path: "Library/Application Support", directoryHint: .isDirectory)

        return LaunchdLocations(
            userAgents: home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory),
            globalAgents: URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory),
            globalDaemons: URL(filePath: "/Library/LaunchDaemons", directoryHint: .isDirectory),
            appleAgents: URL(filePath: "/System/Library/LaunchAgents", directoryHint: .isDirectory),
            appleDaemons: URL(filePath: "/System/Library/LaunchDaemons", directoryHint: .isDirectory),
            applicationSupport: support.appending(path: "Launchd TOC", directoryHint: .isDirectory)
        )
    }
}

enum PlistRepositoryError: LocalizedError, Equatable {
    case invalidRoot
    case invalidPropertyList(String)
    case invalidLabel
    case invalidExecutable
    case invalidInterval
    case invalidCalendarValue(String)
    case unauthorizedPath(String)
    case symbolicLink(String)
    case malformedFile(String)
    case lintFailed(String)
    case targetAlreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            "The property list root must be a dictionary."
        case let .invalidPropertyList(message):
            "The property list is invalid: \(message)"
        case .invalidLabel:
            "The label may contain letters, numbers, periods, hyphens, and underscores only."
        case .invalidExecutable:
            "Provide either Program or at least one ProgramArguments entry."
        case .invalidInterval:
            "StartInterval must be greater than zero."
        case let .invalidCalendarValue(name):
            "The calendar value for \(name) is outside its allowed range."
        case let .unauthorizedPath(path):
            "Launchd TOC cannot modify \(path). Only ~/Library/LaunchAgents is writable."
        case let .symbolicLink(path):
            "Launchd TOC refused a symbolic-link operation at \(path)."
        case let .malformedFile(message):
            "The property list could not be read: \(message)"
        case let .lintFailed(message):
            "plutil rejected the property list: \(message)"
        case .targetAlreadyExists:
            "A launch agent with this filename already exists."
        }
    }
}

final class PlistRepository: @unchecked Sendable {
    private let fileManager: FileManager
    private let commandRunner: any CommandExecuting
    let locations: LaunchdLocations
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        commandRunner: any CommandExecuting = SystemCommandRunner(),
        locations: LaunchdLocations? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.locations = locations ?? .live(fileManager: fileManager)
        self.now = now
    }

    func scan(showAppleServices: Bool) -> [LaunchdJob] {
        var sources: [(URL, JobSource)] = [
            (locations.userAgents, .userAgent),
            (locations.globalAgents, .globalAgent),
            (locations.globalDaemons, .daemon)
        ]
        if showAppleServices {
            sources.append((locations.appleAgents, .appleAgent))
            sources.append((locations.appleDaemons, .appleDaemon))
        }

        return sources.flatMap { directory, source in
            scan(directory: directory, source: source)
        }
    }

    func loadConfiguration(at url: URL) throws -> JobConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw PlistRepositoryError.malformedFile(error.localizedDescription)
        }

        var format = PropertyListSerialization.PropertyListFormat.xml
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )
        } catch {
            throw PlistRepositoryError.malformedFile(error.localizedDescription)
        }

        guard let dictionary = object as? [String: Any] else {
            throw PlistRepositoryError.invalidRoot
        }
        var converted: [String: PropertyListValue] = [:]
        for (key, value) in dictionary {
            guard let convertedValue = PropertyListValue(foundationValue: value) else {
                throw PlistRepositoryError.invalidPropertyList("Unsupported value for \(key)")
            }
            converted[key] = convertedValue
        }

        return JobConfiguration(
            propertyList: converted,
            format: PlistFormat(format),
            fallbackLabel: url.deletingPathExtension().lastPathComponent
        )
    }

    func validate(_ configuration: JobConfiguration) async throws {
        _ = try await serializedData(for: configuration)
    }

    @discardableResult
    func save(_ configuration: JobConfiguration, to url: URL) async throws -> URL {
        let safeURL = try validatedUserAgentURL(url, allowMissing: true)
        let data = try await serializedData(for: configuration)

        try fileManager.createDirectory(
            at: locations.userAgents,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: safeURL.path) {
            try backUp(safeURL, label: configuration.label)
        }
        try data.write(to: safeURL, options: [.atomic])
        return safeURL
    }

    func newAgentURL(label: String) throws -> URL {
        guard Self.isValidLabel(label) else {
            throw PlistRepositoryError.invalidLabel
        }
        let url = locations.userAgents.appending(
            path: "\(label).plist",
            directoryHint: .notDirectory
        )
        _ = try validatedUserAgentURL(url, allowMissing: true)
        guard !fileManager.fileExists(atPath: url.path) else {
            throw PlistRepositoryError.targetAlreadyExists
        }
        return url
    }

    @discardableResult
    func trash(_ url: URL) throws -> URL? {
        let safeURL = try validatedUserAgentURL(url, allowMissing: false)
        var resultingURL: NSURL?
        try fileManager.trashItem(at: safeURL, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    func validatedUserAgentURL(_ url: URL, allowMissing: Bool) throws -> URL {
        let standardized = url.standardizedFileURL
        let fileName = standardized.lastPathComponent
        guard
            fileName == url.lastPathComponent,
            standardized.pathExtension.lowercased() == "plist",
            !fileName.isEmpty,
            fileName != ".plist",
            fileName.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
            !fileName.contains("/"),
            !fileName.contains("\\")
        else {
            throw PlistRepositoryError.unauthorizedPath(url.path)
        }

        let root = locations.userAgents.standardizedFileURL.resolvingSymlinksInPath()
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        guard parent.path == root.path else {
            throw PlistRepositoryError.unauthorizedPath(url.path)
        }

        let exists = fileManager.fileExists(atPath: standardized.path)
        if exists {
            let resourceValues = try standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues.isSymbolicLink == true {
                throw PlistRepositoryError.symbolicLink(standardized.path)
            }
            let canonical = standardized.resolvingSymlinksInPath()
            guard canonical.deletingLastPathComponent().path == root.path else {
                throw PlistRepositoryError.unauthorizedPath(url.path)
            }
        } else if !allowMissing {
            throw CocoaError(.fileNoSuchFile)
        }

        return standardized
    }

    static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 255 else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "-"
                || scalar == "_"
        }
    }

    private func scan(directory: URL, source: JobSource) -> [LaunchdJob] {
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "plist" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                do {
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                    if values.isSymbolicLink == true {
                        throw PlistRepositoryError.symbolicLink(url.path)
                    }
                    let configuration = try loadConfiguration(at: url)
                    return LaunchdJob(
                        plistURL: url,
                        source: source,
                        configuration: configuration
                    )
                } catch {
                    let fallback = JobConfiguration(
                        label: url.deletingPathExtension().lastPathComponent,
                        rawValues: [:]
                    )
                    return LaunchdJob(
                        plistURL: url,
                        source: source,
                        configuration: fallback,
                        runtimeState: .unknown,
                        parseIssue: error.localizedDescription
                    )
                }
            }
    }

    private func serializedData(for configuration: JobConfiguration) async throws -> Data {
        guard Self.isValidLabel(configuration.label) else {
            throw PlistRepositoryError.invalidLabel
        }
        guard configuration.executable?.isEmpty == false else {
            throw PlistRepositoryError.invalidExecutable
        }
        if let interval = configuration.startInterval, interval <= 0 {
            throw PlistRepositoryError.invalidInterval
        }
        try validateCalendar(configuration.calendarSchedules)

        let object = configuration.serializedValues.mapValues(\.foundationValue)
        guard PropertyListSerialization.propertyList(object, isValidFor: configuration.originalFormat.foundationValue) else {
            throw PlistRepositoryError.invalidPropertyList("Foundation rejected the value tree.")
        }

        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: object,
                format: configuration.originalFormat.foundationValue,
                options: 0
            )
        } catch {
            throw PlistRepositoryError.invalidPropertyList(error.localizedDescription)
        }

        let temporaryURL = fileManager.temporaryDirectory.appending(
            path: "launchd-toc-\(UUID().uuidString).plist",
            directoryHint: .notDirectory
        )
        try data.write(to: temporaryURL, options: [.atomic])
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let result = try await commandRunner.run(
            executableURL: URL(filePath: "/usr/bin/plutil"),
            arguments: ["-lint", temporaryURL.path]
        )
        guard result.exitCode == 0 else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw PlistRepositoryError.lintFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }

    private func validateCalendar(_ entries: [CalendarSchedule]) throws {
        for entry in entries {
            let bounds: [(String, Int?, ClosedRange<Int>)] = [
                ("Minute", entry.minute, 0...59),
                ("Hour", entry.hour, 0...23),
                ("Day", entry.day, 1...31),
                ("Weekday", entry.weekday, 0...7),
                ("Month", entry.month, 1...12)
            ]
            for (name, value, range) in bounds {
                if let value, !range.contains(value) {
                    throw PlistRepositoryError.invalidCalendarValue(name)
                }
            }
        }
    }

    private func backUp(_ sourceURL: URL, label: String) throws {
        let backupRoot = locations.applicationSupport
            .appending(path: "Backups", directoryHint: .isDirectory)
            .appending(path: label, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now())
            .replacingOccurrences(of: ":", with: "-")
        let destination = backupRoot.appending(
            path: "\(timestamp).plist",
            directoryHint: .notDirectory
        )
        try fileManager.copyItem(at: sourceURL, to: destination)

        let backups = try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ).sorted { first, second in
            let firstDate = (try? first.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let secondDate = (try? second.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return firstDate > secondDate
        }
        for obsolete in backups.dropFirst(10) {
            try fileManager.removeItem(at: obsolete)
        }
    }
}
