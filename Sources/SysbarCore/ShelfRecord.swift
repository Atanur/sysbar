import Foundation

/// A shelf that was put away before stashes were named: where its files were, and when. Only read, to
/// carry those files over to the main stash.
public struct ShelfRecord: Codable, Equatable, Sendable {
    public var paths: [String]
    public var date: Date

    public init(paths: [String], date: Date) {
        self.paths = paths
        self.date = date
    }
}
