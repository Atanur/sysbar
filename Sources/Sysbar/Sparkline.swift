import SysbarCore
import SwiftUI

/// Minimal line chart. The newest sample is pinned to the right edge and the x scale is fixed to
/// `capacity` samples, so the graph fills from the right as history accumulates.
struct Sparkline: View {
    let values: [Double]
    let capacity: Int
    /// Fixed y range (e.g. 0...1). Nil auto-scales the upper bound with headroom.
    let range: ClosedRange<Double>?
    let color: Color
    var height: CGFloat = 36

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, capacity > 1 else { return }
            let lower = range?.lowerBound ?? 0
            let upper = range?.upperBound ?? max((values.max() ?? 1) * 1.2, 0.1)
            let span = max(upper - lower, .leastNonzeroMagnitude)
            let step = size.width / CGFloat(capacity - 1)

            let points = values.enumerated().map { index, value -> CGPoint in
                let x = size.width - CGFloat(values.count - 1 - index) * step
                let fraction = min(max((value - lower) / span, 0), 1)
                return CGPoint(x: x, y: size.height * (1 - fraction))
            }

            var line = Path()
            line.addLines(points)

            var area = line
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            area.addLine(to: CGPoint(x: points[0].x, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .color(color.opacity(0.15)))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Two series either side of a zero line: `upper` rises from it and `lower` hangs below it. Both
/// share one scale, so equal heights mean equal values. The newest sample is pinned to the right edge.
struct MirroredSparkline: View {
    let upper: [Double]
    let lower: [Double]
    let capacity: Int
    let upperColor: Color
    let lowerColor: Color
    var height: CGFloat = 32

    var body: some View {
        Canvas { context, size in
            guard max(upper.count, lower.count) > 1, capacity > 1 else { return }
            let shares = MirroredScale.fractions(upper: upper, lower: lower)
            let middle = size.height / 2
            let step = size.width / CGFloat(capacity - 1)

            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: middle))
            zero.addLine(to: CGPoint(x: size.width, y: middle))
            context.stroke(zero, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

            func draw(_ fractions: [Double], direction: CGFloat, color: Color) {
                guard fractions.count > 1 else { return }
                let points = fractions.enumerated().map { index, fraction in
                    CGPoint(
                        x: size.width - CGFloat(fractions.count - 1 - index) * step,
                        y: middle - direction * middle * CGFloat(fraction)
                    )
                }
                var line = Path()
                line.addLines(points)
                var area = line
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: middle))
                area.addLine(to: CGPoint(x: points[0].x, y: middle))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.18)))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            draw(shares.upper, direction: 1, color: upperColor)
            draw(shares.lower, direction: -1, color: lowerColor)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
