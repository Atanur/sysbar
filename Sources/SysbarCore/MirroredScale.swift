import Foundation

/// Two series drawn on either side of a zero line (read above and write below, download and upload,
/// the machine's draw and the charge going in) share one scale, so equal heights mean equal values.
public enum MirroredScale {
    /// Space above the highest value, as the single-series graphs leave.
    public static let headroom = 1.2

    /// Each value as a share of the half-height, 0...1. All zeros when there is nothing to show.
    public static func fractions(upper: [Double], lower: [Double]) -> (upper: [Double], lower: [Double]) {
        let peak = (upper + lower).max() ?? 0
        guard peak > 0 else { return (upper.map { _ in 0 }, lower.map { _ in 0 }) }
        let scale = peak * headroom
        func share(_ values: [Double]) -> [Double] { values.map { min(max($0 / scale, 0), 1) } }
        return (share(upper), share(lower))
    }
}
