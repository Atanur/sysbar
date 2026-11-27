import CoreGraphics

/// A signal shown on the closed island's right ear only while it applies; it is not a tab. Clicking it
/// opens the island on the System page with the matching panel unfolded.
public enum NotchStatus: String, CaseIterable, Sendable {
    /// The heat warning.
    case heat
    /// Keep awake is on.
    case keepAwake
}

/// What one place in an ear holds: an item of the layout, or a status glyph.
public enum NotchSlot: Hashable, Sendable {
    case item(NotchItem)
    case status(NotchStatus)
}

/// One entry as laid out in an ear: how wide it is, and whether it is the readouts' bars (which keep
/// more room around them than icons do, for the capsule that marks the System tab).
public struct NotchEarEntry: Equatable, Sendable {
    public let slot: NotchSlot
    public let width: CGFloat
    public let isBars: Bool

    public init(slot: NotchSlot, width: CGFloat, isBars: Bool = false) {
        self.slot = slot
        self.width = width
        self.isBars = isBars
    }

    public init(item: NotchItem, width: CGFloat, isBars: Bool = false) {
        self.init(slot: .item(item), width: width, isBars: isBars)
    }

    /// The layout item, nil for a status glyph.
    public var item: NotchItem? {
        if case .item(let item) = slot { item } else { nil }
    }
}

extension NotchGeometry {
    /// Between the bars and their neighbour in an ear; the System tab's capsule reaches into it.
    public static let barsGap: CGFloat = 8

    /// Between two neighbours in an ear.
    public static func earGap(_ first: NotchEarEntry, _ second: NotchEarEntry) -> CGFloat {
        first.isBars || second.isBars ? barsGap : featureIconGap
    }

    /// Each entry's distance from the ear's start, in order.
    public static func earOffsets(_ entries: [NotchEarEntry]) -> [CGFloat] {
        var offsets: [CGFloat] = []
        var next: CGFloat = 0
        for (index, entry) in entries.enumerated() {
            if index > 0 { next += earGap(entries[index - 1], entry) }
            offsets.append(next)
            next += entry.width
        }
        return offsets
    }

    /// The width of an ear's content.
    public static func earWidth(_ entries: [NotchEarEntry]) -> CGFloat {
        guard let last = entries.last, let offset = earOffsets(entries).last else { return 0 }
        return offset + last.width
    }

    /// The most an ear's content may take.
    public static let earRoom = maxEarWidth - earPadding

    /// The status glyphs the closed island shows, before the ear's items: they are the first to be
    /// noticed and the last to be dropped by `fit`. Only the right ear takes them.
    public static func withStatuses(_ statuses: [NotchStatus], side: CGFloat, before entries: [NotchEarEntry]) -> [NotchEarEntry] {
        statuses.map { NotchEarEntry(slot: .status($0), width: side) } + entries
    }

    /// The entries that fit one ear: while the content is wider than `earRoom`, the one at the far
    /// end from the notch goes, which is the first on the left and the last on the right.
    public static func fit(_ entries: [NotchEarEntry], ear: NotchEar) -> [NotchEarEntry] {
        var kept = entries
        while earWidth(kept) > earRoom, !kept.isEmpty {
            if ear == .left { kept.removeFirst() } else { kept.removeLast() }
        }
        return kept
    }

    /// How much room the bars have in an ear: what the other entries leave of `earRoom`. `entries`
    /// is the ear in order with the bars' entry in it at width zero.
    public static func readoutRoom(_ entries: [NotchEarEntry]) -> CGFloat {
        max(earRoom - earWidth(entries), 0)
    }
}
