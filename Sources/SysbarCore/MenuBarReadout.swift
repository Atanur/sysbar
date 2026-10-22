import Foundation

/// What occupies one place in the menu bar: a pinned metric, or the battery charge.
public enum MenuBarSlot: Hashable, Sendable {
    case metric(MenuBarMetric)
    case battery

    /// Stable name, used to tell readouts apart when deciding whether to redraw.
    public var id: String {
        switch self {
        case .metric(let metric): metric.rawValue
        case .battery: "battery"
        }
    }

    /// The widest text the slot shows, so it keeps its width as the digits change.
    public var widestText: String {
        switch self {
        case .metric(let metric): metric.widestText
        case .battery: "100%"
        }
    }
}

/// What one slot shows in the menu bar: a short label, fixed-width text, and a 0...1 level.
public struct MenuBarReadout: Equatable, Sendable {
    public let slot: MenuBarSlot
    public let label: String
    public let text: String
    public let level: Double
    /// How busy the resource is, for colour. Nil for throughput metrics, which have no "too much".
    /// For the battery it reflects how little charge is left.
    public let load: LoadLevel?
    /// Characters reserved for `text`, so the slot keeps its width as digits change.
    public let slotCharacters: Int

    public var metric: MenuBarMetric? {
        if case .metric(let metric) = slot { return metric }
        return nil
    }

    /// The battery keeps its charge colours even when the other bars are drawn in one colour.
    public var isAlwaysColored: Bool { slot == .battery }
}

public enum MenuBarReadouts {
    /// Power draw that fills the power bar completely.
    public static let powerFullScaleWatts = 30.0
    /// Throughput bars are logarithmic: the top of the scale is 10^6 KiB/s (about 1 GiB/s).
    private static let rateDecades = 6.0

    /// Height of a menu bar level bar, in points.
    public static let barHeight = 13.0
    /// One readout per selected metric, in the order given, then the battery when `batteryThreshold`
    /// says it should be shown. Metrics without a reading, and repeats, are skipped.
    public static func make(
        from snapshot: Snapshot, metrics: [MenuBarMetric], batteryThreshold: Int = BatteryMenuBar.off
    ) -> [MenuBarReadout] {
        let unique = metrics.enumerated().filter { metrics.firstIndex(of: $0.element) == $0.offset }.map(\.element)
        let pinned = unique.compactMap { readout(for: $0, in: snapshot) }
        guard BatteryMenuBar.isShown(snapshot.battery, threshold: batteryThreshold), let battery = snapshot.battery else {
            return pinned
        }
        return pinned + [batteryReadout(battery)]
    }

    /// Maps bytes per second onto 0...1 on a log scale so both a trickle and a burst stay visible.
    static func rateLevel(_ bytesPerSecond: Double) -> Double {
        min(max(log10(1 + bytesPerSecond / 1_024) / rateDecades, 0), 1)
    }

    private static func batteryReadout(_ battery: BatteryInfo) -> MenuBarReadout {
        MenuBarReadout(
            slot: .battery, label: L("Battery"), text: Format.percent(battery.fraction),
            level: min(max(battery.fraction, 0), 1), load: .battery(charge: battery.fraction),
            slotCharacters: MenuBarSlot.battery.widestText.count
        )
    }

    private static func readout(for metric: MenuBarMetric, in snapshot: Snapshot) -> MenuBarReadout? {
        func make(_ text: String, level: Double, load: LoadLevel?) -> MenuBarReadout {
            MenuBarReadout(
                slot: .metric(metric), label: metric.title, text: text,
                level: min(max(level, 0), 1), load: load, slotCharacters: metric.widestText.count
            )
        }

        switch metric {
        case .cpu:
            return make(Format.percent(snapshot.cpuUsage), level: snapshot.cpuUsage, load: LoadLevel(fraction: snapshot.cpuUsage))
        case .gpu:
            return snapshot.gpuUsage.map { make(Format.percent($0), level: $0, load: LoadLevel(fraction: $0)) }
        case .memory:
            return make(
                Format.compactGigabytes(snapshot.memory.usedBytes),
                level: snapshot.memory.fraction,
                load: .memory(fraction: snapshot.memory.fraction, pressure: snapshot.memory.pressure)
            )
        case .power:
            return snapshot.headlinePower.map {
                let level = $0 / powerFullScaleWatts
                return make(Format.compactWatts($0), level: level, load: LoadLevel(fraction: level))
            }
        case .disk:
            return snapshot.disk.map { make(Format.rate($0.total), level: rateLevel($0.total), load: nil) }
        case .network:
            return snapshot.network.map { make(Format.rate($0.total), level: rateLevel($0.total), load: nil) }
        }
    }
}
