import Foundation

/// Every stash, main first. All changes are plain value edits; the app saves the result.
public struct ShelfLibrary: Codable, Equatable, Sendable {
    public private(set) var stashes: [ShelfStash]

    /// What came of a rename.
    public enum RenameOutcome: Equatable, Sendable {
        case renamed, unchanged, empty, taken, notAllowed
    }

    /// Only the main stash.
    public init(now: Date = Date()) {
        stashes = [ShelfStash(id: ShelfStash.mainID, name: ShelfStash.mainName, color: 0, created: now)]
    }

    public var main: ShelfStash { stashes[0] }

    public func stash(_ id: ShelfStash.ID) -> ShelfStash? {
        stashes.first { $0.id == id }
    }

    public var itemCount: Int { stashes.reduce(0) { $0 + $1.items.count } }

    /// A library made of what was read from disk: the main stash is there and first, ids are unique
    /// (a repeated stash gives its items to the first one), each stash holds an item once, names are
    /// trimmed and colours are in range.
    public static func repaired(_ stashes: [ShelfStash], now: Date = Date()) -> ShelfLibrary {
        var merged: [ShelfStash] = []
        for var stash in stashes {
            stash.name = stash.name.trimmingCharacters(in: .whitespacesAndNewlines)
            stash.color = ShelfStash.clamped(stash.color)
            if let index = merged.firstIndex(where: { $0.id == stash.id }) {
                merged[index].items += stash.items
            } else {
                merged.append(stash)
            }
        }
        var library = ShelfLibrary(now: now)
        var rest: [ShelfStash] = []
        for var stash in merged {
            var keys = Set<String>()
            stash.items = stash.items.filter { keys.insert($0.key).inserted }
            if stash.isMain {
                // The main stash keeps its name and its position.
                stash.name = ShelfStash.mainName
                library.stashes[0] = stash
            } else {
                if stash.name.isEmpty { stash.name = "Stash" }
                rest.append(stash)
            }
        }
        library.stashes += rest
        return library
    }

    // MARK: Stashes

    /// True when `name` is already a stash's name or is `reserved`, ignoring case, accents and spaces
    /// at the ends. `ignoring` is the stash being renamed.
    public func isTaken(_ name: String, ignoring id: ShelfStash.ID? = nil, reserved: [String] = []) -> Bool {
        let wanted = Self.fold(name)
        return reserved.contains { Self.fold($0) == wanted }
            || stashes.contains { $0.id != id && Self.fold($0.name) == wanted }
    }

    /// A new stash, last in the list, with the colour the fewest stashes use. `name` is used when it is
    /// free; otherwise `defaultName(n)` with the smallest `n` from 2 that is free ("Stash 2").
    @discardableResult
    public mutating func create(
        name: String? = nil, reserved: [String] = [], now: Date = Date(), defaultName: (Int) -> String
    ) -> ShelfStash.ID {
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var title = wanted
        if title.isEmpty || isTaken(title, reserved: reserved) {
            var number = 2
            while isTaken(defaultName(number), reserved: reserved) { number += 1 }
            title = defaultName(number)
        }
        let stash = ShelfStash(name: title, color: leastUsedColor, created: now)
        stashes.append(stash)
        return stash.id
    }

    /// Renames to the trimmed name. Refused when it is blank, belongs to another stash or to `reserved`,
    /// or the stash is the main one.
    @discardableResult
    public mutating func rename(_ id: ShelfStash.ID, to name: String, reserved: [String] = [], now: Date = Date()) -> RenameOutcome {
        guard let index = stashes.firstIndex(where: { $0.id == id }), !stashes[index].isMain else { return .notAllowed }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return .empty }
        guard title != stashes[index].name else { return .unchanged }
        guard !isTaken(title, ignoring: id, reserved: reserved) else { return .taken }
        stashes[index].name = title
        stashes[index].modified = now
        return .renamed
    }

    public mutating func recolor(_ id: ShelfStash.ID, to color: Int, now: Date = Date()) {
        guard let index = stashes.firstIndex(where: { $0.id == id }) else { return }
        stashes[index].color = ShelfStash.clamped(color)
        stashes[index].modified = now
    }

    /// Deletes a stash, unless it is the main one. Its items go to the main stash, so nothing is lost
    /// with it, unless `movingItemsToMain` is false; the ones the main stash already holds are not repeated.
    @discardableResult
    public mutating func delete(_ id: ShelfStash.ID, movingItemsToMain: Bool = true, now: Date = Date()) -> Bool {
        guard id != ShelfStash.mainID, let index = stashes.firstIndex(where: { $0.id == id }) else { return false }
        let items = stashes[index].items
        stashes.remove(at: index)
        if movingItemsToMain { add(items, to: ShelfStash.mainID, now: now) }
        return true
    }

    // MARK: Items

    /// Adds the items a stash does not hold yet, after the others. Returns the ones that were added.
    @discardableResult
    public mutating func add(_ items: [ShelfItem], to id: ShelfStash.ID, now: Date = Date()) -> [ShelfItem] {
        guard let index = stashes.firstIndex(where: { $0.id == id }) else { return [] }
        var keys = Set(stashes[index].items.map(\.key))
        let fresh = items.filter { keys.insert($0.key).inserted }
        guard !fresh.isEmpty else { return [] }
        stashes[index].items += fresh
        stashes[index].modified = now
        return fresh
    }

    public mutating func remove(_ itemIDs: Set<UUID>, from id: ShelfStash.ID, now: Date = Date()) {
        guard let index = stashes.firstIndex(where: { $0.id == id }),
              stashes[index].items.contains(where: { itemIDs.contains($0.id) }) else { return }
        stashes[index].items.removeAll { itemIDs.contains($0.id) }
        stashes[index].modified = now
    }

    /// Moves items to another stash. One the other stash already holds is just taken out of the first.
    /// Returns how many items left the first stash.
    @discardableResult
    public mutating func move(_ itemIDs: Set<UUID>, from source: ShelfStash.ID, to target: ShelfStash.ID, now: Date = Date()) -> Int {
        guard source != target, let from = stash(source), stash(target) != nil else { return 0 }
        let moving = from.items.filter { itemIDs.contains($0.id) }
        guard !moving.isEmpty else { return 0 }
        remove(Set(moving.map(\.id)), from: source, now: now)
        add(moving, to: target, now: now)
        return moving.count
    }

    /// Replaces items by id wherever they are, such as with their refreshed bookmarks. Nothing else changes.
    public mutating func update(_ items: [ShelfItem]) {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for index in stashes.indices {
            stashes[index].items = stashes[index].items.map { byID[$0.id] ?? $0 }
        }
    }

    /// Puts the files of old recent shelves in the main stash, oldest first so the newest end up last.
    /// Paths that are gone are skipped.
    public mutating func adopt(_ records: [ShelfRecord], now: Date = Date(), fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        let items = records.reversed().flatMap(\.paths).filter(fileExists).map { ShelfItem.file(URL(fileURLWithPath: $0), now: now) }
        add(items, to: ShelfStash.mainID, now: now)
    }

    // MARK: Helpers

    /// The colour fewest stashes use, the lowest index among ties.
    private var leastUsedColor: Int {
        var counts = Array(repeating: 0, count: ShelfStash.paletteSize)
        for stash in stashes { counts[stash.color] += 1 }
        return counts.firstIndex(of: counts.min() ?? 0) ?? 0
    }

    private static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Which stash takes what the Add Clipboard to Stash shortcut adds.
public enum ShelfDefaultStash {
    /// The stash the user chose, while it exists; otherwise the one that last took something, or Main.
    public static func target(chosen: ShelfStash.ID?, lastUsed: ShelfStash.ID, in library: ShelfLibrary) -> ShelfStash.ID {
        if let chosen, library.stash(chosen) != nil { return chosen }
        return library.stash(lastUsed) != nil ? lastUsed : ShelfStash.mainID
    }

    /// The stash id kept in Settings; empty or unreadable means none was chosen.
    public static func chosen(stored: String) -> ShelfStash.ID? {
        UUID(uuidString: stored)
    }
}
