import CSystemBridge
import Foundation

/// macOS's own verdict on how hot the machine is (`ProcessInfo.thermalState`). From `serious` up
/// the system lowers performance to shed heat.
public enum ThermalPressure: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .serious
        }
    }

    public static func < (lhs: ThermalPressure, rhs: ThermalPressure) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One fan's speed and the range it can run in, in revolutions per minute.
public struct FanReading: Equatable, Sendable {
    public let index: Int
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double

    public init(index: Int, rpm: Double, minimum: Double, maximum: Double) {
        self.index = index
        self.rpm = rpm
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Where the fan sits between its minimum (0) and maximum (1) speed.
    public var fraction: Double {
        guard maximum > minimum else { return 0 }
        return min(max((rpm - minimum) / (maximum - minimum), 0), 1)
    }
}

/// The parts that heat up separately, each with its own sensors.
public enum ThermalSource: String, CaseIterable, Sendable {
    case cpu, gpu, memory, battery
}

/// Temperatures by source in °C (missing where a Mac has no such sensors), the fans, and macOS's
/// own thermal state.
public struct ThermalReading: Equatable, Sendable {
    public let temperatures: [ThermalSource: Double]
    public let fans: [FanReading]
    public let pressure: ThermalPressure

    public init(temperatures: [ThermalSource: Double], fans: [FanReading], pressure: ThermalPressure) {
        self.temperatures = temperatures
        self.fans = fans
        self.pressure = pressure
    }

    public func celsius(_ source: ThermalSource) -> Double? { temperatures[source] }

    /// How hard the fans are working, 0...1, averaged over all fans; nil without fans.
    public var fanFraction: Double? {
        fans.isEmpty ? nil : fans.map(\.fraction).reduce(0, +) / Double(fans.count)
    }
}

/// Reads the SMC's temperature sensors by group, and its fans. Apple silicon has dozens of sensors:
/// CPU cores ("Tp…", "Te…", "Tf…"), GPU ("Tg…"), memory ("Tm…") and battery ("TB…"). Each group is
/// summarised by the mean of its hottest half, so idle efficiency cores do not hide a busy
/// cluster and one noisy sensor does not swing the value. The key list is found once, since
/// scanning every SMC key is far slower than reading a few dozen.
public final class ThermalProbe: @unchecked Sendable {
    /// Readings outside this range are sensors that are off or not temperatures at all.
    static let plausibleCelsius = 1.0...130.0
    private static let prefixes: [ThermalSource: [String]] = [
        .cpu: ["Tp", "Te", "Tf"], .gpu: ["Tg"], .memory: ["Tm"], .battery: ["TB"],
    ]

    private struct Keys {
        let sensors: [ThermalSource: [String]]
        let fans: [Int]
    }

    private let lock = NSLock()
    private var keys: Keys?

    public init() {}

    public func read(pressure: ThermalPressure = ThermalPressure(ProcessInfo.processInfo.thermalState)) -> ThermalReading {
        let keys = discoveredKeys()
        let temperatures = keys.sensors.compactMapValues { names in Self.summary(names.compactMap(Self.float)) }
        let fans = keys.fans.compactMap { index -> FanReading? in
            guard
                let rpm = Self.float("F\(index)Ac"), let minimum = Self.float("F\(index)Mn"),
                let maximum = Self.float("F\(index)Mx"), maximum > 0
            else { return nil }
            return FanReading(index: index, rpm: max(rpm, 0), minimum: minimum, maximum: maximum)
        }
        return ThermalReading(temperatures: temperatures, fans: fans, pressure: pressure)
    }

    /// Mean of the hotter half of the plausible readings, or nil when there are none.
    static func summary(_ values: [Double]) -> Double? {
        let usable = values.filter { $0.isFinite && plausibleCelsius.contains($0) }.sorted(by: >)
        guard !usable.isEmpty else { return nil }
        let hotter = usable.prefix((usable.count + 1) / 2)
        return hotter.reduce(0, +) / Double(hotter.count)
    }

    private static func float(_ key: String) -> Double? {
        var value: Float = 0
        guard smc_read_float(key, &value), value.isFinite else { return nil }
        return Double(value)
    }

    private func discoveredKeys() -> Keys {
        lock.lock()
        defer { lock.unlock() }
        if let keys { return keys }
        let temperatureKeys = SystemPower.floatKeys(prefix: "T").map(\.key)
        let sensors = Self.prefixes.compactMapValues { prefixes -> [String]? in
            let names = temperatureKeys.filter { key in prefixes.contains { key.hasPrefix($0) } }
            return names.isEmpty ? nil : names
        }
        let fans = (0..<FanControlLimits.maximumFans).filter { Self.float("F\($0)Mx") != nil }
        let found = Keys(sensors: sensors, fans: fans)
        keys = found
        return found
    }
}
