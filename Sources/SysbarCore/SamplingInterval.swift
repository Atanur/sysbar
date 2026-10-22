import Foundation

/// How often things are sampled, and how much history that keeps.
public enum SamplingInterval {
    /// This Mac: chosen with a slider in tenths of a second.
    public static let localRange: ClosedRange<TimeInterval> = 0.1...5
    public static let localStep: TimeInterval = 0.1
    public static let defaultSeconds: TimeInterval = 2

    /// Remote machines: whole seconds, set per device. Every sample runs a small script on the
    /// server, so the range starts at two seconds to keep the load there low.
    public static let remoteRange: ClosedRange<TimeInterval> = 2...30
    public static let remoteDefaultSeconds: TimeInterval = 5

    /// Every graph holds this many samples, so its time span follows the refresh rate: 15 s at
    /// 0.1 s, 5 minutes at 2 s, 12.5 minutes at 5 s. A fixed count also keeps the drawing cost the
    /// same at every rate.
    public static let historyPoints = 150

    /// Listing every process costs several milliseconds, so the apps table refreshes at most once
    /// a second however fast the rest of the readings are.
    public static let minimumProcessInterval: TimeInterval = 1

    /// How much time a full graph covers at this rate.
    public static func windowSeconds(for interval: TimeInterval) -> TimeInterval {
        (Double(historyPoints) * interval * 10).rounded() / 10
    }

    /// "15 s", "90 s" below two minutes; "5m", "12.5m" above.
    public static func windowText(for interval: TimeInterval) -> String {
        let seconds = windowSeconds(for: interval)
        if seconds < 120 { return L("%@ s", String(format: "%.0f", seconds)) }
        let minutes = seconds / 60
        let text = Format.decimal(minutes, digits: minutes == minutes.rounded() ? 0 : 1)
        return L("%@m", text)
    }

    public static func processInterval(for interval: TimeInterval) -> TimeInterval {
        max(interval, minimumProcessInterval)
    }

    /// Stored values are clamped to the slider's range and step. Zero (never stored), negative
    /// and non-numeric values fall back to the default.
    public static func normalized(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return defaultSeconds }
        let stepped = (value / localStep).rounded() * localStep
        return (min(max(stepped, localRange.lowerBound), localRange.upperBound) * 10).rounded() / 10
    }

    public static func normalizedRemote(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return remoteDefaultSeconds }
        return min(max(value.rounded(.down), remoteRange.lowerBound), remoteRange.upperBound)
    }

    /// "0.1", "2.0" below ten seconds, whole numbers above, for the "%@ s" label.
    public static func text(_ value: TimeInterval) -> String {
        Format.decimal(value, digits: value < 10 ? 1 : 0)
    }
}
