import CoreGraphics
import Foundation

/// Where a floating panel opens beside the pointer.
public enum ShelfFiles {
    /// The panel's bottom-left, in AppKit screen coordinates. Just below and to the right of the
    /// pointer, flipping to the other side when that would leave `visible`.
    public static func origin(size: CGSize, near cursor: CGPoint, visible: CGRect) -> CGPoint {
        let gap: CGFloat = 28
        let drop: CGFloat = 20
        var x = cursor.x + gap
        var y = cursor.y - size.height - drop
        if x + size.width > visible.maxX { x = cursor.x - size.width - gap }
        if y < visible.minY { y = cursor.y + drop }
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return CGPoint(x: min(max(x, visible.minX), maxX), y: min(max(y, visible.minY), maxY))
    }
}

/// A short back-and-forth while a file drag is in progress. A straight drag does not count.
public enum DragShake {
    /// Reversals along one axis before the stash picker opens. Three is a small shake, not a turn.
    public static let reversalsNeeded = 3
    /// How far each swing must go, in points. Eight is a flick of the wrist.
    public static let minTravel: CGFloat = 8

    /// How hard a shake has to be.
    public enum Sensitivity: String, CaseIterable, Sendable {
        case low, standard, high

        public var reversalsNeeded: Int {
            switch self {
            case .low: 4
            case .standard: DragShake.reversalsNeeded
            case .high: 2
            }
        }

        public var minTravel: CGFloat { self == .low ? 12 : DragShake.minTravel }
    }

    public struct Sample: Equatable, Sendable {
        public var x: CGFloat
        public var y: CGFloat

        public init(x: CGFloat, y: CGFloat) {
            self.x = x
            self.y = y
        }
    }

    /// Direction changes after the pointer has travelled at least `minTravel` each way.
    public static func reversals(_ samples: [Sample], minTravel: CGFloat = minTravel) -> Int {
        guard var anchor = samples.first else { return 0 }
        var count = 0
        var direction: CGFloat = 0
        for sample in samples.dropFirst() {
            let dx = sample.x - anchor.x
            let dy = sample.y - anchor.y
            guard max(abs(dx), abs(dy)) >= minTravel else { continue }
            let next: CGFloat = abs(dx) >= abs(dy) ? (dx > 0 ? 1 : -1) : (dy > 0 ? 2 : -2)
            if direction != 0, next != direction, abs(next) == abs(direction) { count += 1 }
            direction = next
            anchor = sample
        }
        return count
    }
}
