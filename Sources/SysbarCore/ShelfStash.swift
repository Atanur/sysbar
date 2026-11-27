import Foundation

/// One thing in a stash: a file the stash remembers by bookmark, or a piece of copied text or a link.
/// A file is never copied. The bookmark finds it again after it is moved or renamed; `path` is the
/// last place it was seen, for the dedupe key and as a fallback.
public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case file, text, link
    }

    /// The longest title kept for text.
    public static let titleLimit = 80

    public var id: UUID
    public var kind: Kind
    /// What the item is called: the file's name, or the first line of the text.
    public var name: String
    /// Where a file was last seen. Empty for text and links.
    public var path: String
    public var bookmark: Data?
    /// The copied text, or the link. Empty for files.
    public var text: String
    public var added: Date

    public init(
        id: UUID = UUID(), kind: Kind, name: String, path: String = "", bookmark: Data? = nil,
        text: String = "", added: Date
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.text = text
        self.added = added
    }

    /// A file. Without a bookmark (the file is not there) it is still kept by path.
    public static func file(_ url: URL, now: Date = Date()) -> ShelfItem {
        let standard = url.standardizedFileURL
        return ShelfItem(
            kind: .file, name: standard.lastPathComponent, path: standard.path,
            bookmark: try? standard.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
            added: now
        )
    }

    /// Copied text, or a link when it is one address and nothing else. Nil for blank text.
    public static func text(_ text: String, now: Date = Date()) -> ShelfItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let title = String(firstLine.trimmingCharacters(in: .whitespaces).prefix(titleLimit))
        return ShelfItem(kind: ClipboardKind.isLink(trimmed) ? .link : .text, name: title, text: trimmed, added: now)
    }

    /// Two items with the same key are the same thing, so a stash holds it once.
    public var key: String {
        kind == .file ? "file:\(path)" : "\(kind.rawValue):\(text)"
    }

    /// Where a file is now.
    public struct Resolution: Equatable, Sendable {
        /// The item with its path, name and bookmark brought up to date.
        public var item: ShelfItem
        /// Where the file is; nil for text and links, and for a file that is gone.
        public var url: URL?
        /// A file that cannot be found any more.
        public var isMissing: Bool
    }

    /// Finds a file again by its bookmark, falling back to the last path. A file in the Trash counts
    /// as gone. Text and links resolve to themselves.
    public func resolved() -> Resolution {
        guard kind == .file else { return Resolution(item: self, url: nil, isMissing: false) }
        var found: URL?
        var stale = false
        if let bookmark {
            var isStale = false
            found = try? URL(
                resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            stale = isStale
        }
        let url = [found, URL(fileURLWithPath: path)].compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path) && !Self.isInTrash($0)
        }
        guard let url else { return Resolution(item: self, url: nil, isMissing: true) }
        var updated = self
        updated.path = url.standardizedFileURL.path
        updated.name = url.lastPathComponent
        if stale || bookmark == nil {
            updated.bookmark = (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? bookmark
        }
        return Resolution(item: updated, url: url, isMissing: false)
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash")
    }
}

/// A named collection of items that stays until the user deletes it. The palette index tells stashes
/// apart by colour; the name does it in words.
public struct ShelfStash: Codable, Equatable, Identifiable, Sendable {
    /// Colours to choose from. The app maps each index to a tint.
    public static let paletteSize = 8
    /// The stash that is always there and cannot be deleted or renamed.
    public static let mainID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// What the main stash is called on disk; the app shows its localized name instead.
    public static let mainName = "Main"

    public var id: UUID
    public var name: String
    public var color: Int
    public var items: [ShelfItem]
    public var created: Date
    public var modified: Date

    // A stash is read leniently: one damaged item or date costs that item, not the whole stash.
    private enum CodingKeys: String, CodingKey { case id, name, color, items, created, modified }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        color = Self.clamped((try? container.decode(Int.self, forKey: .color)) ?? 0)
        items = ((try? container.decode([Lenient<ShelfItem>].self, forKey: .items)) ?? []).compactMap(\.value)
        created = (try? container.decode(Date.self, forKey: .created)) ?? Date()
        modified = (try? container.decode(Date.self, forKey: .modified)) ?? created
    }

    public init(id: UUID = UUID(), name: String, color: Int, items: [ShelfItem] = [], created: Date, modified: Date? = nil) {
        self.id = id
        self.name = name
        self.color = Self.clamped(color)
        self.items = items
        self.created = created
        self.modified = modified ?? created
    }

    public var isMain: Bool { id == Self.mainID }

    /// A palette index that is always in range, whatever was read from disk.
    public static func clamped(_ color: Int) -> Int {
        ((color % paletteSize) + paletteSize) % paletteSize
    }
}

/// Decodes one element, or nothing when it is damaged, so a list survives a bad entry.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
