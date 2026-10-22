import Foundation
import IOKit

/// The state of the internal battery and, when plugged in, its adapter.
public struct BatteryInfo: Equatable, Sendable {
    /// Charge, 0...1.
    public let fraction: Double
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let isFull: Bool
    /// Minutes until empty on battery, or until full while charging. Nil when unknown.
    public let minutesRemaining: Int?
    public let cycleCount: Int?
    /// Maximum capacity relative to when the battery was new, 0...1.
    public let health: Double?
    public let adapterWatts: Int?
    /// Power flowing into (positive) or out of (negative) the battery.
    public let batteryWatts: Double?
}

public enum BatteryProbe {
    /// The registry's marker for an estimate that is not available yet.
    private static let unknownMinutes = 65_535

    /// Nil on machines without a battery.
    public static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return parse(dictionary)
    }

    /// Reads the `AppleSmartBattery` registry properties. Separate from `read()` so it can be tested.
    static func parse(_ properties: [String: Any]) -> BatteryInfo? {
        guard
            flag(properties["BatteryInstalled"]) ?? true,
            let current = integer(properties["CurrentCapacity"]),
            let maximum = integer(properties["MaxCapacity"]), maximum > 0
        else { return nil }

        let plugged = flag(properties["ExternalConnected"]) ?? false
        let charging = flag(properties["IsCharging"]) ?? false
        return BatteryInfo(
            fraction: min(Double(current) / Double(maximum), 1),
            isPluggedIn: plugged,
            isCharging: charging,
            isFull: flag(properties["FullyCharged"]) ?? false,
            minutesRemaining: minutes(properties, plugged: plugged, charging: charging),
            cycleCount: integer(properties["CycleCount"]),
            health: health(properties["BatteryData"] as? [String: Any]),
            adapterWatts: integer((properties["AdapterDetails"] as? [String: Any])?["Watts"]),
            batteryWatts: watts(voltage: integer(properties["Voltage"]), amperage: properties["Amperage"])
        )
    }

    private static func flag(_ value: Any?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func minutes(_ properties: [String: Any], plugged: Bool, charging: Bool) -> Int? {
        let value: Int?
        if charging {
            value = integer(properties["AvgTimeToFull"])
        } else if !plugged {
            value = integer(properties["AvgTimeToEmpty"]) ?? integer(properties["TimeRemaining"])
        } else {
            value = nil
        }
        guard let value, value > 0, value != unknownMinutes else { return nil }
        return value
    }

    private static func health(_ data: [String: Any]?) -> Double? {
        guard
            let nominal = integer(data?["NominalChargeCapacity"]),
            let design = integer(data?["DesignCapacity"]), design > 0
        else { return nil }
        return min(Double(nominal) / Double(design), 1)
    }

    /// Amperage is reported as an unsigned 64-bit number, so a discharge arrives as a huge wrapped
    /// value; reinterpreting the bits restores the sign.
    private static func watts(voltage: Int?, amperage: Any?) -> Double? {
        guard let voltage, let raw = (amperage as? NSNumber)?.uint64Value else { return nil }
        let milliamps = Int64(bitPattern: raw)
        return Double(milliamps) / 1_000 * Double(voltage) / 1_000
    }
}
