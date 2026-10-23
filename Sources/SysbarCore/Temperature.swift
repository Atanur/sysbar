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
