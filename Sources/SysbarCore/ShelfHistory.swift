import Foundation

/// A shelf that was put away: where its files were, and when.
public struct ShelfRecord: Codable, Equatable, Sendable {
    public var paths: [String]
    public var date: Date

    public init(paths: [String], date: Date) {
        self.paths = paths
        self.date = date
    }
}

/// The shelves the menu lists as recent, newest first.
public enum ShelfHistory {
    public static let limit = 20

    /// `record` first. An older shelf holding exactly the same files is replaced, not repeated.
    public static func adding(_ record: ShelfRecord, to list: [ShelfRecord]) -> [ShelfRecord] {
        guard !record.paths.isEmpty else { return list }
        let others = list.filter { Set($0.paths) != Set(record.paths) }
        return Array(([record] + others).prefix(limit))
    }
}
