/// Turns two readings of a cumulative counter into a per-second rate.
public enum CounterRate {
    /// A counter that went backwards (device removed, process id reused) reports 0 rather than a huge value.
    public static func perSecond(previous: UInt64, current: UInt64, seconds: Double) -> Double {
        guard seconds > 0, current >= previous else { return 0 }
        return Double(current - previous) / seconds
    }

    /// For 32-bit kernel counters, which wrap around.
    public static func perSecond32(previous: UInt32, current: UInt32, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(current &- previous) / seconds
    }
}
