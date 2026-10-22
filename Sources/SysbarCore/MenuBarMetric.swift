/// A metric the user can pin to the menu bar. Declaration order is the display order.
public enum MenuBarMetric: String, CaseIterable, Sendable {
    case cpu, gpu, memory, power, disk, network

    public static let defaults: [MenuBarMetric] = [.cpu, .memory, .power]

    /// Short label used in the tooltip, the accessibility text and the card titles.
    public var title: String {
        switch self {
        case .cpu: L("CPU")
        case .gpu: L("GPU")
        case .memory: L("RAM")
        case .power: L("Power")
        case .disk: L("Disk")
        case .network: L("Network")
        }
    }

    /// The widest value this metric shows. The menu bar reserves this much room so the slot never
    /// changes width as the digits change.
    public var widestText: String {
        switch self {
        case .cpu, .gpu: "100%"
        case .memory: "99.9G"
        case .power: "99.9W"
        case .disk, .network: "999M"
        }
    }

    /// Strings written to `UserDefaults`.
    public static func storedValue(of metrics: [MenuBarMetric]) -> [String] {
        OrderedSelection.storedValue(of: metrics)
    }

    /// Reads a stored selection back in display order. Unknown or missing data yields the defaults.
    public static func metrics(fromStored stored: [String]?) -> [MenuBarMetric] {
        let ordered = ordered(fromStored: stored) ?? []
        return ordered.isEmpty ? defaults : ordered
    }

    /// Reads a stored selection in display order. Unlike `metrics(fromStored:)` an empty list stays
    /// empty, and nil (never stored) is reported as nil so the caller can choose its own default.
    public static func ordered(fromStored stored: [String]?) -> [MenuBarMetric]? {
        OrderedSelection.ordered(fromStored: stored)
    }

    /// Adds or removes `metric`. Removing is refused once only `minimum` metrics remain, so the
    /// menu bar can keep at least one while the popover cards may all be hidden.
    public static func toggling(
        _ metric: MenuBarMetric, in current: [MenuBarMetric], minimum: Int = 1
    ) -> [MenuBarMetric] {
        OrderedSelection.toggling(metric, in: current, minimum: minimum)
    }
}
