import Foundation

public enum Format {
    private static let kibibyte = 1_024.0
    private static let mebibyte = 1_048_576.0
    private static let gibibyte = 1_073_741_824.0

    /// The decimal mark of the language Sysbar is shown in: "10,9" in Turkish or German, "10.9" in
    /// English or Japanese. Read once, since the language only changes on relaunch.
    public static let decimalSeparator = decimalSeparator(forLanguage: Bundle.main.preferredLocalizations.first ?? "en")

    public static func decimalSeparator(forLanguage code: String) -> String {
        Locale(identifier: code).decimalSeparator ?? "."
    }

    /// `value` rounded to `digits` decimals, written with the language's decimal mark.
    public static func decimal(_ value: Double, digits: Int, separator: String = decimalSeparator) -> String {
        let text = String(format: "%.\(digits)f", value)
        return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// An app's share of the CPU: "3.6%" below 10%, where one app's share of all cores usually sits
    /// and whole percents would round most rows to "0%", then "23%".
    public static func finePercent(_ fraction: Double, separator: String = decimalSeparator) -> String {
        let percent = fraction * 100
        return percent < 9.95 ? decimal(percent, digits: 1, separator: separator) + "%" : "\(Int(percent.rounded()))%"
    }

    public static func watts(_ value: Double) -> String {
        decimal(value, digits: 1) + " W"
    }

    public static func gigabytes(_ bytes: UInt64) -> String {
        decimal(Double(bytes) / gibibyte, digits: 1) + " GB"
    }

    /// Room left on a disk as Finder writes it, in decimal units: "412 GB", "1.2 TB", "38.5 GB".
    public static func diskSize(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1e12 { return decimal(value / 1e12, digits: 1) + " TB" }
        let gigabytes = value / 1e9
        return decimal(gigabytes, digits: gigabytes >= 100 ? 0 : 1) + " GB"
    }

    /// Menu bar memory text, e.g. "10.9G", dropping the decimal from 100 GB up so it stays five characters.
    public static func compactGigabytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / gibibyte
        return decimal(gigabytes, digits: gigabytes >= 100 ? 0 : 1) + "G"
    }

    /// Installed memory for a card's corner: "16GB", or "7.6GB" when it is not a whole number.
    public static func totalMemory(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / gibibyte
        let whole = abs(gigabytes - gigabytes.rounded()) < 0.05
        return decimal(gigabytes, digits: whole ? 0 : 1) + "GB"
    }

    /// Menu bar power text, e.g. "7.2W", dropping the decimal from 100 W up so it stays five characters.
    public static func compactWatts(_ value: Double) -> String {
        decimal(value, digits: value >= 100 ? 0 : 1) + "W"
    }

    /// Throughput in at most four characters: "0K", "150K", "1.2M", "25M", "1.5G".
    public static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000 * mebibyte { return scaled(bytesPerSecond / gibibyte, "G") }
        if bytesPerSecond >= 1_000 * kibibyte { return scaled(bytesPerSecond / mebibyte, "M") }
        return decimal(bytesPerSecond / kibibyte, digits: 0) + "K"
    }

    /// Per-app memory in the table. Compact keeps every value short: from 100 MB up it is
    /// gigabytes with one decimal ("0.4G", "1.9G", "11G"); smaller values stay in megabytes so
    /// they never round to "0.0G". The detailed form waits until 1000 MB.
    public static func memory(_ bytes: UInt64, compact: Bool = true) -> String {
        let value = Double(bytes)
        let switchAt = compact ? 100.0 : 999.5
        if value / mebibyte >= switchAt {
            return scaled(value / gibibyte, "G")
        }
        return decimal(value / mebibyte, digits: 0) + "M"
    }

    /// Per-app power in the compact table: "38mW", "0.2W", "0.7W", "1.2W", "12W". Below a tenth
    /// of a watt it stays in milliwatts; above that, one decimal keeps the value to two digits and
    /// a symbol.
    public static func compactPower(_ watts: Double) -> String {
        guard watts >= 0.005 else { return "–" }
        if watts >= 1 { return compactWatts(watts) }
        let milliwatts = (watts * 1_000).rounded()
        if milliwatts < 100 { return "\(Int(milliwatts))mW" }
        return decimal((watts * 10).rounded() / 10, digits: 1) + "W"
    }

    /// The table's power when there is room for more detail: "743mW", "150mW", "1.2W".
    public static func detailedPower(_ watts: Double) -> String {
        guard watts >= 0.005 else { return "–" }
        if watts >= 1 { return compactWatts(watts) }
        return "\(Int((watts * 1_000).rounded()))mW"
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
    public static func statusTitle(
        _ snapshot: Snapshot, metrics: [MenuBarMetric], batteryThreshold: Int = BatteryMenuBar.off
    ) -> String {
        let readouts = MenuBarReadouts.make(from: snapshot, metrics: metrics, batteryThreshold: batteryThreshold)
        let parts = readouts.map { "\($0.label) \($0.text)" }
        return parts.isEmpty ? "Sysbar" : parts.joined(separator: " · ")
    }

    private static func scaled(_ value: Double, _ suffix: String) -> String {
        decimal(value, digits: value < 10 ? 1 : 0) + suffix
    }
}
