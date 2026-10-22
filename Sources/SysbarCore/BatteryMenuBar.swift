/// When the battery charge joins the menu bar: only on battery power, and only once the charge is
/// at or below a chosen percentage. Zero turns it off; 100 shows it whenever the Mac is unplugged.
public enum BatteryMenuBar {
    public static let off = 0
    public static let thresholds = [off, 100, 80, 50, 20]
    public static let defaultThreshold = 50

    /// Stored values that are not one of the choices fall back to the default.
    public static func normalized(_ value: Int?) -> Int {
        guard let value, thresholds.contains(value) else { return defaultThreshold }
        return value
    }

    public static func isShown(_ battery: BatteryInfo?, threshold: Int) -> Bool {
        guard let battery, threshold > off, !battery.isPluggedIn else { return false }
        return percent(battery.fraction) <= threshold
    }

    static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}

extension LoadLevel {
    /// Charge read the other way round from load: plenty left is calm, little left is an alarm.
    public static func battery(charge: Double) -> LoadLevel {
        switch BatteryMenuBar.percent(charge) {
        case 51...: .low
        case 36...: .moderate
        case 21...: .high
        default: .critical
        }
    }
}
