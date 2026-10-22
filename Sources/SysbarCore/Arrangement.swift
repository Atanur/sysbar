/// Every case of an enum in the user's order, with some of them switched on. The menu bar readouts
/// and the popover cards use it so they can be both chosen and rearranged.
public struct Arrangement<Item>: Equatable, Sendable
where Item: CaseIterable & Hashable & Sendable & RawRepresentable, Item.RawValue == String {
    /// Every case exactly once, in the user's order.
    public let order: [Item]
    private let enabled: Set<Item>

    public init(order: [Item], selected: [Item]) {
        self.order = Self.complete(order)
        enabled = Set(selected)
    }

    /// Reads stored names. Unknown and repeated names are ignored; cases missing from the stored
    /// order (such as ones added in a later version) go at the end in declaration order. A missing
    /// selection, or an empty one when `emptyMeansDefault` is set, falls back to `defaultSelection`.
    public init(
        storedOrder: [String]?, storedSelection: [String]?, defaultSelection: [Item], emptyMeansDefault: Bool
    ) {
        let order = (storedOrder ?? []).compactMap(Item.init(rawValue:))
        let selection = storedSelection.map { $0.compactMap(Item.init(rawValue:)) }
        let useDefault = selection == nil || (emptyMeansDefault && selection?.isEmpty == true)
        self.init(order: order, selected: useDefault ? defaultSelection : selection ?? [])
    }

    /// The switched-on cases, in the user's order.
    public var selected: [Item] { order.filter(enabled.contains) }

    public func contains(_ item: Item) -> Bool { enabled.contains(item) }

    /// Switches `item` on or off. Switching off is refused once only `minimum` cases remain on.
    public func toggling(_ item: Item, minimum: Int) -> Arrangement {
        if enabled.contains(item) {
            guard enabled.count > minimum else { return self }
            return Arrangement(order: order, selected: selected.filter { $0 != item })
        }
        return Arrangement(order: order, selected: selected + [item])
    }

    /// Moves `item` into `target`'s place: after it when moving down, before it when moving up.
    public func moving(_ item: Item, to target: Item) -> Arrangement {
        guard item != target, let from = order.firstIndex(of: item), let to = order.firstIndex(of: target) else {
            return self
        }
        let rest = order.filter { $0 != item }
        let anchor = rest.firstIndex(of: target) ?? rest.endIndex
        let index = from < to ? anchor + 1 : anchor
        return Arrangement(order: Array(rest[..<index]) + [item] + Array(rest[index...]), selected: selected)
    }

    /// Moves `item` up (negative) or down (positive) by `offset` places, stopping at either end.
    public func moving(_ item: Item, by offset: Int) -> Arrangement {
        guard let from = order.firstIndex(of: item) else { return self }
        let to = min(max(from + offset, 0), order.count - 1)
        return moving(item, to: order[to])
    }

    public var storedOrder: [String] { order.map(\.rawValue) }
    public var storedSelection: [String] { selected.map(\.rawValue) }

    /// Each case once, keeping the first occurrence, followed by any that are missing.
    private static func complete(_ order: [Item]) -> [Item] {
        let unique = order.enumerated().filter { order.firstIndex(of: $0.element) == $0.offset }.map(\.element)
        return unique + Item.allCases.filter { !unique.contains($0) }
    }
}
