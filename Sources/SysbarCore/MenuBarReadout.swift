import Foundation

/// What one metric shows in the menu bar: a short label, fixed-width text, and a 0...1 bar level.
public struct MenuBarReadout: Equatable, Sendable {
    public let metric: MenuBarMetric
    public let label: String
    public let text: String
    public let level: Double
    /// How busy the resource is, for colour. Nil for throughput metrics, which have no "too much".
    public let load: LoadLevel?
    /// Characters reserved for `text`, so the slot keeps its width as digits change.
    public let slotCharacters: Int
}

public enum MenuBarReadouts {
    /// Power draw that fills the power bar completely.
    public static let powerFullScaleWatts = 30.0
    /// Throughput bars are logarithmic: the top of the scale is 10^6 KiB/s (about 1 GiB/s).
    private static let rateDecades = 6.0

    /// Height of a menu bar level bar, in points.
    public static let barHeight = 13.0
    /// One readout per selected metric, in display order. Metrics without a reading are skipped.
    public static func make(from snapshot: Snapshot, metrics: [MenuBarMetric]) -> [MenuBarReadout] {
        MenuBarMetric.allCases.filter(metrics.contains).compactMap { readout(for: $0, in: snapshot) }
    }

    /// Maps bytes per second onto 0...1 on a log scale so both a trickle and a burst stay visible.
    static func rateLevel(_ bytesPerSecond: Double) -> Double {
        min(max(log10(1 + bytesPerSecond / 1_024) / rateDecades, 0), 1)
    }

    private static func readout(for metric: MenuBarMetric, in snapshot: Snapshot) -> MenuBarReadout? {
        func make(_ text: String, level: Double, load: LoadLevel?) -> MenuBarReadout {
            MenuBarReadout(
                metric: metric, label: metric.title, text: text,
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
