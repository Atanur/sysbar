import CoreGraphics
import Foundation

/// A short trip of the mouse cursor away from where it rests and back, drawn so it looks like a hand
/// moved it: curved paths that differ every time, a gentle start and stop, and a pause at the far end.
/// Posting it makes the Mac's idle clock start again, which is what chat apps read to show "away".
public struct MouseRoute: Sendable, Equatable {
    /// A cubic Bézier curve.
    struct Curve: Sendable, Equatable {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        func point(at t: Double) -> CGPoint {
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(
                x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                y: a * start.y + b * control1.y + c * control2.y + d * end.y
            )
        }
    }

    let out: Curve
    let back: Curve
    let bounds: CGRect
    public let outSeconds: Double
    public let dwellSeconds: Double
    public let backSeconds: Double

    public var totalSeconds: Double { outSeconds + dwellSeconds + backSeconds }

    /// Where the cursor is `elapsed` seconds after the route began: it starts and ends where it rested.
    public func position(at elapsed: Double) -> CGPoint {
        let point: CGPoint
        if elapsed <= outSeconds {
            point = out.point(at: Self.ease(elapsed / outSeconds))
        } else if elapsed <= outSeconds + dwellSeconds {
            point = out.end
        } else {
            point = back.point(at: Self.ease((elapsed - outSeconds - dwellSeconds) / backSeconds))
        }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    /// Slow at both ends, quick in the middle, as a hand's movement is.
    private static func ease(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

public enum MouseWander {
    /// How long the Mac must have been left alone before the cursor moves; the move itself starts the
    /// clock again, so it comes about once a minute for as long as nobody touches the Mac.
    public static let idleSecondsBeforeMoving = 60.0
    /// How often the idle time is looked at.
    public static let pollSeconds = 5.0

    /// A cursor this close (in points) to the middle of the screen is already there, so it goes to the
    /// lower right instead.
    static let nearCenterRadius = 200.0
    /// How far in from the lower right corner that spot lies, as a share of the screen's width and
    /// height: clear of the corner, where macOS may have a hot corner (Quick Note by default).
    static let cornerInset = 0.15
    /// The time of each leg before the distance is counted in, and the time each point of distance adds.
    static let outDurations = 0.35...0.7
    static let dwellDurations = 0.15...0.4
    static let backDurations = 0.4...0.8
    static let secondsPerPoint = 1.0 / 1500

    public static func isDue(idleSeconds: Double) -> Bool {
        idleSeconds >= idleSecondsBeforeMoving
    }

    /// Where the cursor goes: the middle of the screen, or the lower right when it already is near the middle.
    static func target(from origin: CGPoint, within bounds: CGRect) -> CGPoint {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let fromCenter = ((origin.x - center.x) * (origin.x - center.x) + (origin.y - center.y) * (origin.y - center.y)).squareRoot()
        guard fromCenter <= nearCenterRadius else { return center }
        return CGPoint(x: bounds.maxX - bounds.width * cornerInset, y: bounds.maxY - bounds.height * cornerInset)
    }

    /// A route from `origin` to the middle of the screen (or the lower right), and back. `bounds` is
    /// the screen the cursor is on; the route never leaves it.
    public static func route<G: RandomNumberGenerator>(
        from origin: CGPoint, within bounds: CGRect, using generator: inout G
    ) -> MouseRoute {
        let target = target(from: origin, within: bounds)
        let distance = ((target.x - origin.x) * (target.x - origin.x) + (target.y - origin.y) * (target.y - origin.y)).squareRoot()
        let travel = distance * secondsPerPoint
        return MouseRoute(
            out: curve(from: origin, to: target, using: &generator),
            back: curve(from: target, to: origin, using: &generator),
            bounds: bounds,
            outSeconds: Double.random(in: outDurations, using: &generator) + travel,
            dwellSeconds: Double.random(in: dwellDurations, using: &generator),
            backSeconds: Double.random(in: backDurations, using: &generator) + travel
        )
    }

    /// A curve that bows to one side by a different amount each time, as a hand's path does.
    private static func curve<G: RandomNumberGenerator>(
        from start: CGPoint, to end: CGPoint, using generator: inout G
    ) -> MouseRoute.Curve {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return MouseRoute.Curve(start: start, control1: start, control2: end, end: end) }
        let sideways = CGPoint(x: -dy / length, y: dx / length)
        let bow1 = Double.random(in: -0.25...0.25, using: &generator) * length
        let bow2 = Double.random(in: -0.15...0.15, using: &generator) * length
        return MouseRoute.Curve(
            start: start,
            control1: CGPoint(x: start.x + dx * 0.3 + sideways.x * bow1, y: start.y + dy * 0.3 + sideways.y * bow1),
            control2: CGPoint(x: start.x + dx * 0.7 + sideways.x * bow2, y: start.y + dy * 0.7 + sideways.y * bow2),
            end: end
        )
    }
}
