import Foundation

/// The stashes on disk: one JSON file in a folder only this user can read. The user curates this data,
/// so a file that cannot be read is moved aside, never deleted.
public struct ShelfStashStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The folder the stashes live in, below the one the user chose.
    public static let folderName = "Stashes"

    /// The stashes' folder for a stored location (see `StorageLocation`).
    public static func directory(parentStored: String) -> URL {
        StorageLocation.parent(stored: parentStored).appendingPathComponent(folderName, isDirectory: true)
    }

    /// ~/Library/Application Support/Sysbar/Stashes
    public static var standardDirectory: URL { directory(parentStored: "") }

    /// The file's layout. A newer layout this version cannot read is treated like a damaged file.
    private struct Envelope: Codable {
        static let currentVersion = 1
        var version: Int
        var stashes: [ShelfStash]

        init(version: Int, stashes: [ShelfStash]) {
            self.version = version
            self.stashes = stashes
        }

        /// One damaged stash is left out; the others are kept.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            stashes = try container.decode([Lenient<ShelfStash>].self, forKey: .stashes).compactMap(\.value)
        }

        private enum CodingKeys: String, CodingKey { case version, stashes }
    }

    /// What `load` found.
    public struct Loaded: Sendable {
        public var library: ShelfLibrary
        /// There was no file yet: the first run, when older data can be carried over.
        public var isFirstRun: Bool
        /// The file was unreadable and was moved aside, to a name starting with `corruptFilePrefix`.
        public var recovered: Bool
    }

    public static let fileName = "stashes.json"
    public static let corruptFilePrefix = "stashes.corrupt"
    private var file: URL { directory.appendingPathComponent(Self.fileName) }

    public func load(now: Date = Date()) -> Loaded {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else {
            return Loaded(library: ShelfLibrary(now: now), isFirstRun: true, recovered: false)
        }
        if let data = try? Data(contentsOf: file),
           let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.version <= Envelope.currentVersion {
            return Loaded(library: .repaired(envelope.stashes, now: now), isFirstRun: false, recovered: false)
        }
        // Never over an earlier one: each damaged file is kept.
        var aside = directory.appendingPathComponent("\(Self.corruptFilePrefix)-\(Int(now.timeIntervalSince1970)).json")
        var attempt = 1
        while manager.fileExists(atPath: aside.path) {
            attempt += 1
            aside = directory.appendingPathComponent("\(Self.corruptFilePrefix)-\(Int(now.timeIntervalSince1970))-\(attempt).json")
        }
        try? manager.moveItem(at: file, to: aside)
        return Loaded(library: ShelfLibrary(now: now), isFirstRun: false, recovered: true)
    }

    /// Whether a stashes file has been saved here.
    public var hasStashes: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// Moves the stashes file to `destination`: copied, checked, and only then deleted here. Refused
    /// when the destination already holds stashes, which are never overwritten.
    public func moved(to destination: ShelfStashStore) throws {
        guard !destination.hasStashes else { throw StorageMoveError.destinationHasData }
        try StorageMove.move(names: [Self.fileName], from: directory, to: destination.directory)
    }

    public func save(_ library: ShelfLibrary) throws {
        try prepareDirectory()
        let data = try JSONEncoder().encode(Envelope(version: Envelope.currentVersion, stashes: library.stashes))
        try data.write(to: file, options: .atomic)
    }

    private func prepareDirectory() throws {
        let manager = FileManager.default
        let privateOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        if manager.fileExists(atPath: directory.path) {
            try manager.setAttributes(privateOnly, ofItemAtPath: directory.path)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: privateOnly)
        }
    }
}
