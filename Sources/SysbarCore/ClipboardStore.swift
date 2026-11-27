import Foundation

/// The clipboard history on disk: an index of entries, and beside it one file per image or rich
/// text. The folder is readable by this user only.
public struct ClipboardStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The folder the history lives in, below the one the user chose.
    public static let folderName = "Clipboard"

    /// The history's folder for a stored location (see `StorageLocation`).
    public static func directory(parentStored: String) -> URL {
        StorageLocation.parent(stored: parentStored).appendingPathComponent(folderName, isDirectory: true)
    }

    /// ~/Library/Application Support/Sysbar/Clipboard
    public static var standardDirectory: URL { directory(parentStored: "") }

    private static let indexName = "history.json"
    private var index: URL { directory.appendingPathComponent(Self.indexName) }

    /// The saved entries. One whose file is gone is left out, and files no entry names are deleted,
    /// so an interrupted save never leaves copies behind.
    /// An unreadable index counts as empty, so the files it named are deleted too.
    public func load() -> [ClipboardEntry] {
        let stored = (try? Data(contentsOf: index)).flatMap { try? JSONDecoder().decode([ClipboardEntry].self, from: $0) } ?? []
        let entries = stored.filter { entry in
            entry.fileName.map { FileManager.default.fileExists(atPath: url(of: $0).path) } ?? true
        }
        let named = Set(entries.compactMap(\.fileName) + [Self.indexName])
        let present = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        // Only files this store could have written: a folder the user chose may hold other things.
        for name in present where !named.contains(name) && Self.isItemFile(name) {
            try? FileManager.default.removeItem(at: url(of: name))
        }
        return entries
    }

    /// Whether a history has been saved here.
    public var hasHistory: Bool { FileManager.default.fileExists(atPath: index.path) }

    /// What the history takes on disk, in bytes.
    public func sizeOnDisk() -> Int64 {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.reduce(0) { total, name in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(of: name).path)[.size]) as? Int64
            return total + (size ?? 0)
        }
    }

    /// Moves the history to `destination`: copied, checked, and only then deleted here. Refused when
    /// the destination already holds a history, which is never overwritten.
    public func moved(to destination: ClipboardStore) throws {
        guard !destination.hasHistory else { throw StorageMoveError.destinationHasData }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        try StorageMove.move(
            names: names.filter { $0 == Self.indexName || Self.isItemFile($0) }, from: directory, to: destination.directory
        )
    }

    /// An image or rich text file: an entry's id and its extension.
    private static func isItemFile(_ name: String) -> Bool {
        let file = name as NSString
        return ["png", "rtf"].contains(file.pathExtension) && UUID(uuidString: file.deletingPathExtension) != nil
    }

    public func save(_ entries: [ClipboardEntry]) throws {
        try prepareDirectory()
        try JSONEncoder().encode(entries).write(to: index, options: .atomic)
    }

    /// Keeps the image or rich text of `entry`. Entries of other kinds have no file, so nothing is written.
    public func write(_ data: Data, for entry: ClipboardEntry) throws {
        guard let name = entry.fileName else { return }
        try prepareDirectory()
        try data.write(to: url(of: name), options: .atomic)
    }

    public func data(for entry: ClipboardEntry) -> Data? {
        entry.fileName.flatMap { try? Data(contentsOf: url(of: $0)) }
    }

    /// Deletes the files of entries no longer kept. The index is saved separately.
    public func remove(_ entries: [ClipboardEntry]) {
        for name in entries.compactMap(\.fileName) {
            try? FileManager.default.removeItem(at: url(of: name))
        }
    }

    /// Deletes the whole history, index and files.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(of name: String) -> URL {
        directory.appendingPathComponent(name)
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
