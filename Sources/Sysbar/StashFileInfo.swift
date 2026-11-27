import AppKit

/// What a stash row shows about a file: its icon and the name of its folder. Both come from the file
/// system, which can be slow (a cold lookup, a network volume), so they are read once, off the main
/// thread, and kept; a row draws a placeholder until its file's turn comes.
enum StashFileInfo {
    final class Entry {
        let icon: NSImage
        let folder: String

        init(icon: NSImage, folder: String) {
            self.icon = icon
            self.folder = folder
        }
    }

    /// Thread safe, and it forgets the least used entries on its own, so removed files do not pile up.
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 1_000
        return cache
    }()

    /// What is known about the file at `path` so far; nil until `load` has read it.
    static func cached(_ path: String) -> Entry? { cache.object(forKey: path as NSString) }

    /// Reads the file's icon and folder name unless that has been done, and returns them. Call it off the main thread.
    @discardableResult
    static func load(_ path: String) -> Entry {
        if let known = cached(path) { return known }
        let url = URL(fileURLWithPath: path)
        let entry = Entry(
            icon: NSWorkspace.shared.icon(forFile: path),
            folder: FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        )
        cache.setObject(entry, forKey: path as NSString)
        return entry
    }

    /// Reads many files in the background, so the rows find them ready when a stash is shown.
    static func prefetch(_ paths: [String]) {
        for path in paths where cached(path) == nil { load(path) }
    }
}
