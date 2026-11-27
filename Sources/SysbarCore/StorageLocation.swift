import Foundation

/// Where a feature keeps its data. Settings store the folder the user chose; each feature keeps its
/// files in a folder of its own below it, so a chosen folder such as Documents is never tidied or
/// locked as if it were the store.
public enum StorageLocation {
    /// ~/Library/Application Support/Sysbar: where the data has always been.
    public static var defaultParent: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Sysbar", isDirectory: true)
    }

    /// The folder a stored path names, tidied. Nothing stored, a path that is not absolute, or the
    /// root of the disk means the default folder.
    public static func parent(stored: String) -> URL {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return defaultParent }
        let tidy = (expanded as NSString).standardizingPath
        guard tidy != "/" else { return defaultParent }
        return URL(fileURLWithPath: tidy, isDirectory: true)
    }

    /// What to store for a chosen folder: nothing for the default one.
    public static func storedValue(for url: URL) -> String {
        let tidy = url.standardizedFileURL.path
        return tidy == defaultParent.standardizedFileURL.path ? "" : tidy
    }

    /// `path` with the home folder as "~", for showing.
    public static func displayPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Why data could not be moved to a new folder.
public enum StorageMoveError: Error, Equatable, Sendable {
    /// The new folder already holds data of this kind; moving never overwrites it.
    case destinationHasData
}

/// Moving files between folders: copy, check, and only then delete the originals.
enum StorageMove {
    static func move(names: [String], from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        let present = names.filter { manager.fileExists(atPath: source.appendingPathComponent($0).path) }
        guard !present.isEmpty else { return }
        try manager.createDirectory(
            at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        var copied: [String] = []
        do {
            for name in present {
                let from = source.appendingPathComponent(name)
                let to = destination.appendingPathComponent(name)
                try manager.copyItem(at: from, to: to)
                copied.append(name)
                guard size(of: from) == size(of: to) else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            // Leave the source whole and the destination as it was.
            for name in copied { try? manager.removeItem(at: destination.appendingPathComponent(name)) }
            throw error
        }
        for name in present { try? manager.removeItem(at: source.appendingPathComponent(name)) }
        if (try? manager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? manager.removeItem(at: source)
        }
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }
}
