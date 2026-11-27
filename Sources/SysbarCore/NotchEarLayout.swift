import Foundation

/// One thing the island's ears can hold. The System item is the readouts' bars as one; the others are
/// feature icons. The raw value is the name the settings keep it under. A layout stored by a version
/// that had Fans and Keep awake items loses them on reading: those are buttons of the System page now.
public enum NotchItem: String, CaseIterable, Codable, Sendable {
    case system, stash, clipboard

    /// Where the item sits until the user moves it: the readouts left of the notch, the icons right of it.
    public var defaultEar: NotchEar { self == .system ? .left : .right }
}

/// The two halves of the island, either side of the notch.
public enum NotchEar: String, CaseIterable, Codable, Sendable {
    case left, right

    public var opposite: NotchEar { self == .left ? .right : .left }
}

/// Whether an item shows on the closed island. There is no fully hidden choice: the ears are the open
/// panel's only tabs, and a feature goes away by being turned off on its own page.
public enum NotchVisibility: String, CaseIterable, Codable, Sendable {
    /// Closed and open.
    case always
    /// Not on the closed island; it appears, in its place, when the island opens.
    case whenOpen
}

/// What the user put in each ear: the items in order from left to right, and which of them show only
/// while the island is open. Always normalised: every item is in exactly one ear.
public struct NotchEarLayout: Equatable, Codable, Sendable {
    public private(set) var left: [NotchItem]
    public private(set) var right: [NotchItem]
    public private(set) var whenOpen: Set<NotchItem>

    /// The island as it was before the ears were configurable.
    public static let standard = NotchEarLayout(left: [.system], right: [.stash, .clipboard])

    /// Duplicates are dropped (the first place wins, the left ear's before the right's), and an item
    /// that is in neither ear is appended to its default one, so a layout is always complete.
    public init(left: [NotchItem], right: [NotchItem], whenOpen: Set<NotchItem> = []) {
        var seen = Set<NotchItem>()
        var ears: [NotchEar: [NotchItem]] = [.left: [], .right: []]
        for (ear, items) in [(NotchEar.left, left), (.right, right)] {
            for item in items where seen.insert(item).inserted { ears[ear, default: []].append(item) }
        }
        for item in NotchItem.allCases where seen.insert(item).inserted { ears[item.defaultEar, default: []].append(item) }
        self.left = ears[.left] ?? []
        self.right = ears[.right] ?? []
        self.whenOpen = whenOpen
    }

    private enum CodingKeys: String, CodingKey { case left, right, whenOpen }

    /// Lenient: an item this version does not know (from a newer one) is skipped, not an error.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func items(_ key: CodingKeys) -> [NotchItem] {
            ((try? container.decode([String].self, forKey: key)) ?? []).compactMap(NotchItem.init(rawValue:))
        }
        self.init(left: items(.left), right: items(.right), whenOpen: Set(items(.whenOpen)))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(left.map(\.rawValue), forKey: .left)
        try container.encode(right.map(\.rawValue), forKey: .right)
        try container.encode(NotchItem.allCases.filter(whenOpen.contains).map(\.rawValue), forKey: .whenOpen)
    }

    /// Before the ears were configurable the right ear's icons could be switched off, which left them
    /// out of the closed island and out of nothing else: the open island has always shown every
    /// feature's tab. Those are now "only when open", which is what they were.
    public static func migrated(hiddenFeatures: [String]) -> NotchEarLayout {
        let hidden = Set(hiddenFeatures.compactMap(NotchItem.init(rawValue:)))
        return NotchEarLayout(left: standard.left, right: standard.right, whenOpen: hidden)
    }

    public func items(on ear: NotchEar) -> [NotchItem] { ear == .left ? left : right }

    public func ear(of item: NotchItem) -> NotchEar { left.contains(item) ? .left : .right }

    public func visibility(of item: NotchItem) -> NotchVisibility { whenOpen.contains(item) ? .whenOpen : .always }

    public func setting(_ item: NotchItem, to visibility: NotchVisibility) -> NotchEarLayout {
        var next = whenOpen
        if visibility == .whenOpen { next.insert(item) } else { next.remove(item) }
        return NotchEarLayout(left: left, right: right, whenOpen: next)
    }

    /// `item` taken out of its ear and put in `ear` at `index` (counted after it was taken out; clamped).
    public func moving(_ item: NotchItem, to ear: NotchEar, at index: Int = .max) -> NotchEarLayout {
        var ears: [NotchEar: [NotchItem]] = [.left: left.filter { $0 != item }, .right: right.filter { $0 != item }]
        var target = ears[ear] ?? []
        target.insert(item, at: min(max(index, 0), target.count))
        ears[ear] = target
        return NotchEarLayout(left: ears[.left] ?? [], right: ears[.right] ?? [], whenOpen: whenOpen)
    }

    /// `item` one place along in its own ear, towards the start for a negative `offset`.
    public func shifting(_ item: NotchItem, by offset: Int) -> NotchEarLayout {
        let ear = ear(of: item)
        let items = items(on: ear)
        guard let index = items.firstIndex(of: item) else { return self }
        return moving(item, to: ear, at: index + offset)
    }

    /// `item` placed before `other`, in `other`'s ear: what dropping one row on another does.
    public func moving(_ item: NotchItem, before other: NotchItem) -> NotchEarLayout {
        guard item != other else { return self }
        let ear = ear(of: other)
        let rest = items(on: ear).filter { $0 != item }
        return moving(item, to: ear, at: rest.firstIndex(of: other) ?? rest.count)
    }

    /// The items each ear shows: those that are `available` (the System item always is; a feature
    /// only while it is on), and while the island is closed only those shown always.
    public func ears(available: Set<NotchItem>, open: Bool) -> (left: [NotchItem], right: [NotchItem]) {
        func shown(_ items: [NotchItem]) -> [NotchItem] {
            items.filter { available.contains($0) && (open || !whenOpen.contains($0)) }
        }
        return (shown(left), shown(right))
    }
}
