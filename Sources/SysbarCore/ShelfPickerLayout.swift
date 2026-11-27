import CoreGraphics
import Foundation

/// The stash picker that opens while files are dragged: one tile per stash and a last one for a new
/// stash, in a grid. Coordinates run down from the top left, as in a flipped view, and the grid
/// starts `top` points down so it clears the notch.
public struct ShelfPickerLayout: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case stash(UUID)
        case newStash
    }

    public struct Tile: Equatable, Sendable {
        public var target: Target
        public var frame: CGRect
    }

    public static let tileSize = CGSize(width: 156, height: 36)
    public static let gap: CGFloat = 8
    public static let inset: CGFloat = 12
    public static let maxColumns = 3

    public let size: CGSize
    public let tiles: [Tile]

    /// A grid for `stashes`, at least `minWidth` wide, with `top` points above it.
    public init(stashes: [UUID], top: CGFloat = 0, minWidth: CGFloat = 0) {
        let targets = stashes.map(Target.stash) + [.newStash]
        let columns = min(Self.maxColumns, targets.count)
        let rows = (targets.count + columns - 1) / columns
        let gridWidth = CGFloat(columns) * Self.tileSize.width + CGFloat(columns - 1) * Self.gap
        let width = max(gridWidth + 2 * Self.inset, minWidth)
        let left = (width - gridWidth) / 2
        tiles = targets.enumerated().map { index, target in
            let origin = CGPoint(
                x: left + CGFloat(index % columns) * (Self.tileSize.width + Self.gap),
                y: top + Self.inset + CGFloat(index / columns) * (Self.tileSize.height + Self.gap)
            )
            return Tile(target: target, frame: CGRect(origin: origin, size: Self.tileSize))
        }
        let height = top + Self.inset + CGFloat(rows) * Self.tileSize.height + CGFloat(rows - 1) * Self.gap + Self.inset
        size = CGSize(width: width, height: height)
    }

    /// The tile under `point`, with half a gap of slack so a drop between two tiles still lands.
    public func target(at point: CGPoint) -> Target? {
        tiles.first { $0.frame.insetBy(dx: -Self.gap / 2, dy: -Self.gap / 2).contains(point) }?.target
    }
}
