import Foundation

struct ReleaseAsset: Decodable, Hashable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable, Hashable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol HTTPFetching: Sendable {
    func get(_ url: URL) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPFetching {
    func get(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Launchd-TOC", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(data: data, statusCode: status)
    }
}

enum UpdateResult: Hashable, Sendable {
    case updateAvailable(GitHubRelease, downloadURL: URL?)
    case upToDate
    case noRelease
}

enum UpdateCheckError: LocalizedError, Equatable, Sendable {
    case rateLimited
    case server(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            "GitHub’s anonymous API rate limit has been reached. Try again later."
        case let .server(status):
            "GitHub returned HTTP \(status)."
        case .malformedResponse:
            "The release response was not in the expected format."
        }
    }
}

actor UpdateChecker {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/thierryc/launchd-toc/releases/latest"
    )!

    private let httpClient: any HTTPFetching

    init(httpClient: any HTTPFetching = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func check(currentVersion: String) async throws -> UpdateResult {
        let response = try await httpClient.get(Self.latestReleaseURL)
        switch response.statusCode {
        case 200:
            break
        case 404:
            return .noRelease
        case 403, 429:
            throw UpdateCheckError.rateLimited
        default:
            throw UpdateCheckError.server(response.statusCode)
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: response.data)
        } catch {
            throw UpdateCheckError.malformedResponse
        }
        guard !release.draft, !release.prerelease else { return .noRelease }

        guard
            let available = SemanticVersion(release.tagName),
            let current = SemanticVersion(currentVersion)
        else {
            throw UpdateCheckError.malformedResponse
        }
        guard available > current else { return .upToDate }

        let dmg = release.assets.first {
            $0.name.lowercased().hasSuffix(".dmg")
                && $0.name.lowercased().contains("universal")
        }?.browserDownloadURL
        return .updateAvailable(release, downloadURL: dmg)
    }
}

struct SemanticVersion: Comparable, Hashable, Sendable {
    let components: [Int]

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "v", with: "", options: [.anchored])
        let stable = normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
        let parsed = stable.split(separator: ".").compactMap { Int($0) }
        guard !parsed.isEmpty, parsed.count == stable.split(separator: ".").count else { return nil }
        components = parsed
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return false }
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        var normalized = components
        while normalized.last == 0 {
            normalized.removeLast()
        }
        hasher.combine(normalized)
    }
}
