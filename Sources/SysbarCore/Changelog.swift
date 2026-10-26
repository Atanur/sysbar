import Foundation

/// One version's notes from `CHANGELOG.md`.
public struct ChangelogRelease: Equatable, Sendable {
    public let version: AppVersion
    /// "2026-10-27", as written in the heading.
    public let date: String?
    /// The changes as plain sentences, without Markdown marks.
    public let items: [String]
}

/// Reads the changelog the app ships with, and the bullets of a GitHub release's notes. Both are the
/// same Markdown: a `## 0.5.3 — 2026-10-27` heading per version followed by `- ` items.
public enum Changelog {
    private static let headingPrefix = "## "
    private static let bulletPrefixes = ["- ", "* "]

    /// Every versioned section, in the file's order. Headings that are not a version
    /// ("Unreleased") are skipped along with their items.
    public static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var heading: (version: AppVersion, date: String?)?
        var lines: [Substring] = []

        func finish() {
            if let heading {
                releases.append(ChangelogRelease(version: heading.version, date: heading.date, items: items(of: lines)))
            }
            lines = []
        }

        for line in markdown.split(whereSeparator: \.isNewline) {
            if line.hasPrefix(headingPrefix) {
                finish()
                heading = parseHeading(line.dropFirst(headingPrefix.count))
            } else {
                lines.append(line)
            }
        }
        finish()
        return releases
    }

    public static func release(_ version: AppVersion?, in releases: [ChangelogRelease]) -> ChangelogRelease? {
        guard let version else { return nil }
        return releases.first { $0.version == version }
    }

    /// The bullet items of any Markdown text, such as a release body, up to `limit` of them.
    public static func items(in text: String, limit: Int = .max) -> [String] {
        Array(items(of: text.split(whereSeparator: \.isNewline)).prefix(limit))
    }

    /// "0.5.3 — 2026-10-27" or just "0.5.3".
    private static func parseHeading(_ text: Substring) -> (version: AppVersion, date: String?)? {
        let parts = text.split { $0 == " " || $0 == "—" || $0 == "–" }
        guard let first = parts.first, let version = AppVersion(String(first)) else { return nil }
        return (version, parts.dropFirst().first.map(String.init))
    }

    /// Bullets, with an indented line joined to the item above it; anything else ends an item.
    private static func items(of lines: [Substring]) -> [String] {
        var items: [String] = []
        var current: String?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let prefix = bulletPrefixes.first(where: { line.hasPrefix($0) }) {
                current.map { items.append($0) }
                current = String(line.dropFirst(prefix.count))
            } else if let item = current, !line.isEmpty, raw.first == " " {
                current = item + " " + line
            } else {
                current.map { items.append($0) }
                current = nil
            }
        }
        current.map { items.append($0) }
        return items.map(plain).filter { !$0.isEmpty }
    }

    /// Drops emphasis and code marks and keeps a link's text.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
