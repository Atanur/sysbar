import Foundation

/// A release version such as 0.1.2, read from a tag like "v0.1.2". Missing parts count as zero, so
/// 1.0 and 1.0.0 are the same version. Anything other than dot-separated numbers is rejected.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        guard (1...4).contains(parts.count), numbers.count == parts.count, numbers.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        components = numbers
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (left, right) = padded(lhs, rhs)
        return left == right
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (left, right) = padded(lhs, rhs)
        return left.lexicographicallyPrecedes(right)
    }

    private static func padded(_ lhs: AppVersion, _ rhs: AppVersion) -> ([Int], [Int]) {
        let count = max(lhs.components.count, rhs.components.count)
        func pad(_ parts: [Int]) -> [Int] { parts + Array(repeating: 0, count: count - parts.count) }
        return (pad(lhs.components), pad(rhs.components))
    }
}

/// A published release that can be offered: its version, its page, and the app archive.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let pageURL: URL
    /// The `Sysbar-<version>.zip` asset; nil when the release has none, in which case the update
    /// is offered through the release page.
    public let downloadURL: URL?
}

public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/atanur/sysbar/releases/latest")!
    /// Automatic checks happen at most this often.
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Only links into this repository are ever opened or downloaded.
    private static let repositoryPath = "/atanur/sysbar/"

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back must not postpone checks for good.
        return now.timeIntervalSince(lastCheck) >= checkInterval || lastCheck > now
    }

    /// Reads GitHub's "latest release" reply. Drafts, pre-releases, tags that are not versions, and
    /// links that lead outside this repository all yield nil.
    public static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard
            let reply = try? JSONDecoder().decode(Reply.self, from: data),
            !(reply.draft ?? false), !(reply.prerelease ?? false),
            let version = AppVersion(reply.tagName),
            let page = URL(string: reply.htmlURL), isRepositoryLink(page)
        else { return nil }

        let archiveName = "Sysbar-\(version).zip"
        let archive = reply.assets?
            .first { $0.name == archiveName }
            .flatMap { URL(string: $0.browserDownloadURL) }
            .flatMap { isRepositoryLink($0) && $0.path.contains("/releases/download/") ? $0 : nil }
        return ReleaseInfo(version: version, pageURL: page, downloadURL: archive)
    }

    /// The release to suggest, if it is newer than the running version and not one the user skipped.
    public static func offer(_ release: ReleaseInfo?, current: AppVersion?, skipped: AppVersion?) -> ReleaseInfo? {
        guard let release, let current, current < release.version else { return nil }
        if let skipped, skipped == release.version { return nil }
        return release
    }

    /// Plain https links on github.com under this repository: no port, no credentials, and no
    /// "." or ".." segments that could climb out of it once normalised.
    static func isRepositoryLink(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "github.com"
            && url.port == nil && url.user == nil && url.password == nil
            && !url.pathComponents.contains { $0 == "." || $0 == ".." }
            && url.path.lowercased().hasPrefix(repositoryPath)
    }

    private struct Reply: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name, browserDownloadURL = "browser_download_url"
        }
    }
}
