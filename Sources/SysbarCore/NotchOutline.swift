import CoreGraphics

/// The radii of the open island's outline: the closed strip with the panel hanging from its bottom
/// edge, drawn as one shape. Where the panel is wider than the strip, the strip's side flows into the
/// panel's top edge through a concave fillet, and the panel's outer top corner is convex; the bottom
/// corners match the top ones, so the panel reads as one rounded shape. Pure arithmetic, so the shape
/// can be tested without drawing it.
///
/// The curves are Apple's continuous ones, which reach `continuousReach` times their radius along each
/// straight edge they leave, so a radius is only as large as that reach allows: the room beside the
/// strip, the strip's side, and the panel's height all shrink it, and with no overhang there is no
/// curve on that side at all and the strip's edge simply carries on down.
public struct NotchOutline: Equatable, Sendable {
    /// What one side of the strip does where it meets the panel.
    public struct Side: Equatable, Sendable {
        /// The concave curve from the strip's side out onto the panel's top edge.
        public var fillet: CGFloat
        /// The convex curve of the panel's outer top corner.
        public var corner: CGFloat
        public static let none = Side(fillet: 0, corner: 0)
    }

    /// How far along an edge a continuous curve of radius 1 reaches.
    public static let continuousReach: CGFloat = 1.53
    public static let preferredFillet: CGFloat = 12
    public static let preferredCorner: CGFloat = 14

    public let left: Side
    public let right: Side
    /// The panel's two bottom corners: no rounder than its top corners, where it has any.
    public let bottom: CGFloat

    /// - Parameters:
    ///   - strip: where the strip is across `width`, the panel's width.
    ///   - sideRoom: how much of the strip's side is straight, for a fillet to rise along.
    ///   - bodyHeight: the panel's height so far; the radii grow with it, so a panel just starting to
    ///     open is still a plain strip.
    ///   - bottomCorner: the radius the panel's bottom corners would like.
    public init(strip: ClosedRange<CGFloat>, width: CGFloat, sideRoom: CGFloat, bodyHeight: CGFloat, bottomCorner: CGFloat) {
        let height = max(bodyHeight, 0)
        func side(overhang: CGFloat) -> Side {
            guard overhang >= 1, height > 0 else { return .none }
            let budget = overhang / Self.continuousReach
            let corner = min(Self.preferredCorner, budget / 2, height / 2)
            let fillet = min(Self.preferredFillet, budget - corner, max(sideRoom, 0) / Self.continuousReach, height / 2)
            return Side(fillet: max(fillet, 0), corner: max(corner, 0))
        }
        left = side(overhang: strip.lowerBound)
        right = side(overhang: width - strip.upperBound)
        let top = max(left.corner, right.corner)
        let fitted = min(bottomCorner, height / 2, width / 2)
        bottom = max(top > 0 ? min(fitted, top) : fitted, 0)
    }
}
