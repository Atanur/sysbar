import Foundation

/// Words for the power card: a short note for its header and the details for its tooltip.
/// What matters differs by situation: on battery it is the charge and how long it lasts; on an
/// adapter it is what the machine draws from the wall.
public enum PowerSummary {
    /// "67% · 4h 27m" on battery, "78% · charging" or "100% · on power" on an adapter. Nil without a battery.
    public static func headline(battery: BatteryInfo?) -> String? {
        guard let battery else { return nil }
        let percent = Format.percent(battery.fraction)
        if !battery.isPluggedIn {
            return battery.minutesRemaining.map { "\(percent) · \(Format.compactDuration(minutes: $0))" } ?? percent
        }
        return "\(percent) · " + (battery.isCharging ? L("charging") : L("on power"))
    }

    /// Details that fit the situation, or nil when there is nothing to add.
    public static func detail(battery: BatteryInfo?, systemPower: Double?) -> String? {
        guard let battery else { return nil }
        let parts = battery.isPluggedIn ? adapterParts(battery, systemPower) : batteryParts(battery)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func batteryParts(_ battery: BatteryInfo) -> [String] {
        var parts: [String] = []
        if let watts = battery.batteryWatts { parts.append(L("Battery draw %@ W", String(format: "%.1f", abs(watts)))) }
        if let cycles = battery.cycleCount { parts.append(L("%@ cycles", "\(cycles)")) }
        if let health = battery.health { parts.append(L("health %@", Format.percent(health))) }
        return parts
    }

    /// The wall draw is what the machine uses plus what is going into the battery.
    private static func adapterParts(_ battery: BatteryInfo, _ systemPower: Double?) -> [String] {
        var parts: [String] = []
        if let adapter = battery.adapterWatts { parts.append(L("Adapter %@ W", "\(adapter)")) }
        if let systemPower {
            let wall = systemPower + max(battery.batteryWatts ?? 0, 0)
            parts.append(L("~%@ W from the wall", String(format: "%.0f", wall)))
        }
        if battery.isCharging, let watts = battery.batteryWatts, watts >= 0.5 {
            parts.append(L("charging +%@ W", String(format: "%.0f", watts)))
        }
        if battery.isCharging, let minutes = battery.minutesRemaining {
            parts.append(L("full in %@", Format.compactDuration(minutes: minutes)))
        }
        return parts
    }
}
