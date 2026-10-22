/// Rules for a user-chosen subset of an enum's cases that is kept in the enum's declaration order
/// and stored as raw strings. Shared by the menu bar metrics and the app table columns.
public enum OrderedSelection {
    /// Reads a stored selection in declaration order. Unknown strings are ignored, an empty list
    /// stays empty, and nil (never stored) is reported as nil so the caller can pick a default.
    public static func ordered<Item>(fromStored stored: [String]?) -> [Item]?
    where Item: CaseIterable & Hashable & RawRepresentable, Item.RawValue == String {
        guard let stored else { return nil }
        let parsed = Set(stored.compactMap { Item(rawValue: $0) })
        return Item.allCases.filter(parsed.contains)
    }

    /// Adds or removes `item`. Removing is refused once only `minimum` items remain.
    public static func toggling<Item>(_ item: Item, in current: [Item], minimum: Int) -> [Item]
    where Item: CaseIterable & Hashable & RawRepresentable, Item.RawValue == String {
        if current.contains(item) {
            return current.count > minimum ? current.filter { $0 != item } : current
        }
        return Item.allCases.filter { $0 == item || current.contains($0) }
    }

    /// Strings written to `UserDefaults`.
    public static func storedValue<Item>(of items: [Item]) -> [String]
    where Item: RawRepresentable, Item.RawValue == String {
        items.map(\.rawValue)
    }
}
