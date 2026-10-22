import Foundation

public enum Format {
    private static let kibibyte = 1_024.0
    private static let mebibyte = 1_048_576.0
    private static let gibibyte = 1_073_741_824.0

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    public static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / gibibyte)
    }

    /// Menu bar memory text, e.g. "10.9G", dropping the decimal from 100 GB up so it stays five characters.
    public static func compactGigabytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / gibibyte
        return gigabytes >= 100 ? String(format: "%.0fG", gigabytes) : String(format: "%.1fG", gigabytes)
    }

    /// Installed memory for a card's corner: "16GB", or "7.6GB" when it is not a whole number.
    public static func totalMemory(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / gibibyte
        let whole = abs(gigabytes - gigabytes.rounded()) < 0.05
        return String(format: whole ? "%.0fGB" : "%.1fGB", gigabytes)
    }

    /// Menu bar power text, e.g. "7.2W", dropping the decimal from 100 W up so it stays five characters.
    public static func compactWatts(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0fW", value) : String(format: "%.1fW", value)
    }

    /// Throughput in at most four characters: "0K", "150K", "1.2M", "25M", "1.5G".
    public static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000 * mebibyte { return scaled(bytesPerSecond / gibibyte, "G") }
        if bytesPerSecond >= 1_000 * kibibyte { return scaled(bytesPerSecond / mebibyte, "M") }
        return String(format: "%.0fK", bytesPerSecond / kibibyte)
    }

    /// Per-app memory: "340M" below one gigabyte, "1.5G" above.
    public static func memory(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        return value >= gibibyte ? scaled(value / gibibyte, "G") : String(format: "%.0fM", value / mebibyte)
    }

    /// Short duration for tight spaces: "4h 27m", "45m", "1h".
    public static func compactDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 { return rest > 0 ? L("%1$@h %2$@m", "\(hours)", "\(rest)") : L("%@h", "\(hours)") }
        return L("%@m", "\(rest)")
    }

    /// Uptime using its two largest units: "2d 4h", "3h 5m", "59m".
    public static func uptime(_ seconds: TimeInterval) -> String {
        let minutesTotal = Int(max(seconds, 0)) / 60
        let days = minutesTotal / 1_440
        let hours = minutesTotal % 1_440 / 60
        let minutes = minutesTotal % 60
        if days > 0 { return L("%1$@d %2$@h", "\(days)", "\(hours)") }
        if hours > 0 { return L("%1$@h %2$@m", "\(hours)", "\(minutes)") }
        return L("%@m", "\(minutes)")
    }

    /// Tooltip and accessibility text for the pinned metrics, e.g. "CPU 23% · RAM 10.6G · Power 12.3W".
    public static func statusTitle(_ snapshot: Snapshot, metrics: [MenuBarMetric]) -> String {
        let parts = MenuBarReadouts.make(from: snapshot, metrics: metrics).map { "\($0.label) \($0.text)" }
        return parts.isEmpty ? "Sysbar" : parts.joined(separator: " · ")
    }

    private static func scaled(_ value: Double, _ suffix: String) -> String {
        String(format: value < 10 ? "%.1f%@" : "%.0f%@", value, suffix)
    }
}
