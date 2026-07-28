import AppKit
import Foundation

enum LogStream: String, CaseIterable, Identifiable, Sendable {
    case standardOutput
    case standardError

    var id: String { rawValue }
    var title: String { self == .standardOutput ? "stdout" : "stderr" }
}

enum LogTailerError: LocalizedError {
    case unavailable
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .unavailable: "This job does not define a log file for the selected stream."
        case .unsafePath: "Launchd TOC only clears regular, non-symlinked log files in your home folder."
        }
    }
}

actor LogTailer {
    private let fileManager: FileManager
    private let maximumBytes: UInt64

    init(fileManager: FileManager = .default, maximumBytes: UInt64 = 64 * 1_024) {
        self.fileManager = fileManager
        self.maximumBytes = maximumBytes
    }

    func tail(url: URL?) throws -> String {
        guard let url else { throw LogTailerError.unavailable }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let end = try handle.seekToEnd()
        let start = end > maximumBytes ? end - maximumBytes : 0
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        return text
    }

    func canClear(url: URL?) -> Bool {
        guard let url else { return false }
        let home = fileManager.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix(home.path + "/") else { return false }
        guard
            let values = try? standardized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            return false
        }
        return standardized.resolvingSymlinksInPath().path.hasPrefix(home.path + "/")
    }

    func clear(url: URL?) throws {
        guard canClear(url: url), let url else { throw LogTailerError.unsafePath }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
    }

    nonisolated func open(url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
