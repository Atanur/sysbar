/// How busy a resource is, for colour coding. Thresholds are shared by every metric so the
/// same colour always means the same thing.
public enum LoadLevel: Equatable, Sendable {
    case low, moderate, high, critical

    private static let moderateFrom = 0.5
    private static let highFrom = 0.75
    private static let criticalFrom = 0.9

    /// `fraction` is 0...1. Anything outside that range, or not a number, is clamped so a bad
    /// reading never raises an alarm.
    public init(fraction: Double) {
        guard fraction.isFinite else {
            self = .low
            return
        }
        switch fraction {
        case ..<Self.moderateFrom: self = .low
        case ..<Self.highFrom: self = .moderate
        case ..<Self.criticalFrom: self = .high
        default: self = .critical
        }
    }

    /// Memory is judged by the kernel's pressure level first: a full but healthy cache is normal.
    public static func memory(fraction: Double, pressure: MemoryPressure) -> LoadLevel {
        switch pressure {
        case .critical: .critical
        case .warning: .high
        case .normal: fraction >= criticalFrom ? .moderate : .low
        }
    }
}
