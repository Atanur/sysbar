import CoreGraphics
import Foundation

/// Where a shelf that was not summoned by a shake first appears.
public enum ShelfPlacement: String, CaseIterable, Sendable {
    case topRight, topLeft, bottomRight, bottomLeft, center
}

/// What happens to files that arrive from the clipboard or the notch.
public enum ShelfAddBehavior: String, CaseIterable, Sendable {
    /// A new shelf beside the others.
    case newShelf
    /// Added to the shelf used last.
    case currentShelf
}

/// The key that summons the shelf while it is held during a file drag.
public enum ShelfModifier: String, CaseIterable, Sendable {
    case shift, option, control, command
}

/// How the notch drop zone shows itself during a file drag.
public enum ShelfNotchStyle: String, CaseIterable, Sendable {
    case hover, always
}

/// The screen edge a shelf is docked to.
public enum ShelfDockEdge: Sendable {
    case left, right
}

/// A global shortcut. `modifiers` holds `NSEvent.ModifierFlags` raw values (⇧ 1<<17, ⌃ 1<<18,
/// ⌥ 1<<19, ⌘ 1<<20); `key` is what to show for the key, such as "A" or "Space".
public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt
    public var key: String

    public init(keyCode: UInt16, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// "⌥⇧A": modifiers in the order macOS writes them, then the key.
    public var display: String {
        let glyphs: [(UInt, String)] = [(1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘")]
        return glyphs.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
    }

    /// The key as a menu item's key equivalent, for the hint beside an item. Nil for keys a menu cannot show.
    public var menuKey: String? {
        if key == "Space" { return " " }
        return key.count == 1 ? key.lowercased() : nil
    }
}

extension ShelfFiles {
    /// The shelf's bottom-left in AppKit screen coordinates for a default `placement`, 12 points
    /// in from the edges of `visible`. A shelf that would cover one of `others` goes beside it,
    /// further from the corner; when the row is full it cascades instead.
    public static func origin(
        size: CGSize, placement: ShelfPlacement, visible: CGRect, avoiding others: [CGRect] = []
    ) -> CGPoint {
        let margin: CGFloat = 12
        let left = visible.minX + margin
        let right = visible.maxX - size.width - margin
        let bottom = visible.minY + margin
        let top = visible.maxY - size.height - margin
        let midX = visible.midX - size.width / 2
        let midY = visible.midY - size.height / 2
        let base: CGPoint
        switch placement {
        case .topRight: base = CGPoint(x: right, y: top)
        case .topLeft: base = CGPoint(x: left, y: top)
        case .bottomRight: base = CGPoint(x: right, y: bottom)
        case .bottomLeft: base = CGPoint(x: left, y: bottom)
        case .center: base = CGPoint(x: midX, y: midY)
        }
        guard !others.isEmpty else { return base }
        let sideways: CGFloat = placement == .topRight || placement == .bottomRight ? -1 : 1
        let vertical: CGFloat = placement == .bottomLeft || placement == .bottomRight ? 1 : -1
        var point = base
        for _ in 0..<8 {
            let rect = CGRect(origin: point, size: size)
            if !others.contains(where: { $0.intersects(rect) }) { return point }
            point.x += sideways * (size.width + margin)
            guard point.x >= visible.minX, point.x + size.width <= visible.maxX else { break }
        }
        let cascade = 24 * CGFloat(min(others.count, 8))
        return CGPoint(x: base.x + sideways * cascade, y: base.y + vertical * cascade)
    }
}

extension ShelfFiles {
    /// The part of a docked shelf that shows: a tab against the screen edge.
    public static let dockSize = CGSize(width: 30, height: 180)
    /// How far a docked shelf reaches past the screen edge, hiding the tab's outer corners so it sits flush.
    public static let dockOverhang: CGFloat = 22

    /// The edge a shelf released at `frame` docks to: the one it is pushed against, within `threshold`.
    /// A default corner leaves a 12-point margin, so it is not mistaken for an edge.
    public static func dockEdge(of frame: CGRect, in visible: CGRect, threshold: CGFloat = 8) -> ShelfDockEdge? {
        if frame.minX <= visible.minX + threshold { return .left }
        if frame.maxX >= visible.maxX - threshold { return .right }
        return nil
    }

    /// The frame of a docked tab, near `midY`. A tab never sits on one of `others`: it moves up or down by whole tabs.
    public static func dockFrame(
        edge: ShelfDockEdge, in visible: CGRect, midY: CGFloat, avoiding others: [CGRect] = []
    ) -> CGRect {
        let size = CGSize(width: dockSize.width + dockOverhang, height: dockSize.height)
        let x = edge == .left ? visible.minX - dockOverhang : visible.maxX - dockSize.width
        let lowest = visible.minY + 8
        let highest = visible.maxY - size.height - 8
        let wanted = min(max(midY - size.height / 2, lowest), max(lowest, highest))
        let step = size.height + 8
        for attempt in 0..<12 {
            // 0, +1, -1, +2, -2 ... tabs from where it was dropped.
            let offset = CGFloat((attempt + 1) / 2) * step * (attempt % 2 == 1 ? 1 : -1)
            let y = wanted + offset
            guard y >= lowest, y <= highest else { continue }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            if !others.contains(where: { $0.intersects(frame) }) { return frame }
        }
        return CGRect(x: x, y: wanted, width: size.width, height: size.height)
    }

    /// Where a shelf of `size` opens from a tab: 12 points in from the edge, at the tab's height.
    public static func undockedOrigin(edge: ShelfDockEdge, size: CGSize, in visible: CGRect, midY: CGFloat) -> CGPoint {
        let margin: CGFloat = 12
        let x = edge == .left ? visible.minX + margin : visible.maxX - size.width - margin
        let lowest = visible.minY + margin
        let y = min(max(midY - size.height / 2, lowest), max(lowest, visible.maxY - size.height - margin))
        return CGPoint(x: x, y: y)
    }
}
