import AppKit
import SwiftUI
import SysbarCore

/// The island's outline as one path in the island view's flipped coordinates (origin top left): the
/// closed strip, or the strip with the panel hanging from its bottom edge. Black is filled with it
/// and glass is masked by it, so both are the same shape.
enum IslandOutline {
    /// The closed island: around the notch a rectangle whose top corners sit above the view, so it meets
    /// the screen edge square as the notch does; otherwise a capsule.
    static func closed(size: CGSize, shape: NotchGeometry.Shape, corner: CGFloat) -> CGPath {
        switch shape {
        case .notch:
            continuous(CGRect(x: 0, y: -corner, width: size.width, height: size.height + corner), radius: corner)
        case .capsule:
            continuous(CGRect(origin: .zero, size: size), radius: size.height / 2)
        }
    }

    /// The strip (`header` tall, across `strip`) and the panel below it, as wide as the view and as tall
    /// as what is left. Where the panel is wider than the strip, concave fillets join the strip's sides
    /// to the panel's top edge, and the panel's outer top corners are convex.
    static func popup(
        size: CGSize, shape: NotchGeometry.Shape, strip: ClosedRange<CGFloat>, header: CGFloat, bottomCorner: CGFloat
    ) -> CGPath {
        let bodyHeight = max(size.height - header, 0)
        let isNotch = shape == .notch
        // A capsule's strip keeps its round top corners; around the notch they sit above the screen edge.
        let stripCorner = isNotch ? 0 : header / 2
        let radii = NotchOutline(
            strip: strip, width: size.width, sideRoom: header - stripCorner, bodyHeight: bodyHeight, bottomCorner: bottomCorner
        )
        let top: CGFloat = isNotch ? -2 : 0
        let overlap = min(1, bodyHeight)
        let stripRect = CGRect(x: strip.lowerBound, y: top, width: strip.upperBound - strip.lowerBound, height: header + overlap - top)
        var path = UnevenRoundedRectangle(
            topLeadingRadius: stripCorner, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: stripCorner,
            style: .continuous
        ).path(in: stripRect).cgPath
        guard bodyHeight > 0 else { return path }
        let body = UnevenRoundedRectangle(
            topLeadingRadius: radii.left.corner, bottomLeadingRadius: radii.bottom,
            bottomTrailingRadius: radii.bottom, topTrailingRadius: radii.right.corner, style: .continuous
        ).path(in: CGRect(x: 0, y: header, width: size.width, height: bodyHeight)).cgPath
        path = path.union(body)
        if let fillet = fillet(radius: radii.left.fillet, at: CGPoint(x: strip.lowerBound, y: header), outward: -1) {
            path = path.union(fillet)
        }
        if let fillet = fillet(radius: radii.right.fillet, at: CGPoint(x: strip.upperBound, y: header), outward: 1) {
            path = path.union(fillet)
        }
        return path
    }

    /// The sliver in the corner where the strip's side (`joint` is its bottom) meets the panel's top
    /// edge, going `outward` (1 right, -1 left): a square with a continuous rounded rectangle taken out,
    /// whose one corner is the concave curve. It overlaps the strip and the panel by a point, so the
    /// union has no seam.
    private static func fillet(radius: CGFloat, at joint: CGPoint, outward: CGFloat) -> CGPath? {
        guard radius > 0.5 else { return nil }
        let side = 2 * radius
        let square = CGRect(x: outward > 0 ? joint.x - 1 : joint.x - side, y: joint.y - side, width: side + 1, height: side + 1)
        let cutter = CGRect(x: outward > 0 ? joint.x : joint.x - 4 * radius, y: joint.y - 4 * radius, width: 4 * radius, height: 4 * radius)
        return CGPath(rect: square, transform: nil).subtracting(continuous(cutter, radius: radius))
    }

    private static func continuous(_ rect: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
    }
}
