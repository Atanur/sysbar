import CSystemBridge
import Foundation

public enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit

    /// Fahrenheit where the region uses US customary units, Celsius everywhere else.
    public static var regionDefault: TemperatureUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// "64°", rounded to whole degrees in this unit.
    public func format(celsius: Double) -> String {
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }
}

/// CPU die temperature from the SMC. Apple silicon reports one sensor per core cluster region
/// ("Tp…" keys, older chips "Te…"); their average is what system tools call the CPU temperature.
/// The key list is found once, since scanning every SMC key is far slower than reading a few.
public final class CPUTemperatureProbe: @unchecked Sendable {
    /// Readings outside this range are sensors that are off or not temperatures at all.
    static let plausibleCelsius = 1.0...130.0

    private let lock = NSLock()
    private var keys: [String]?

    public init() {}

    public func read() -> Double? {
        let values = sensorKeys().compactMap { key -> Double? in
            var value: Float = 0
            guard smc_read_float(key, &value) else { return nil }
            return Double(value)
        }
        return Self.average(values)
    }

    /// Mean of the plausible readings, or nil when there are none.
    static func average(_ values: [Double]) -> Double? {
        let usable = values.filter { $0.isFinite && plausibleCelsius.contains($0) }
        guard !usable.isEmpty else { return nil }
        return usable.reduce(0, +) / Double(usable.count)
    }

    private func sensorKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        if let keys { return keys }
        let found = ["Tp", "Te"].lazy
            .map { SystemPower.floatKeys(prefix: $0).map(\.key) }
            .first { !$0.isEmpty } ?? []
        keys = found
        return found
    }
}
