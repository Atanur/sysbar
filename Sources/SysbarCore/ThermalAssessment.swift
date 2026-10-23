import Foundation

/// Why the Mac is as warm as it is, in order of how much it matters to the user.
public enum ThermalCause: String, Equatable, Sendable {
    /// macOS reports serious or critical thermal pressure and is slowing the Mac to cool it.
    case throttling
    /// The fans are running fast, yet the heat is not going away: blocked vents, a soft surface,
    /// a hot room, or a load the cooling cannot keep up with.
    case cannotCool
    /// Both the processor and the graphics processor are busy.
    case heavyWork
    /// The graphics processor is busy: language models, rendering, games.
    case gpuWork
    /// The processor is busy.
    case cpuWork
    /// Little is running and temperatures are falling after work.
    case coolingDown
    /// Little is running but the Mac stays warm: heat soaked in, or warm surroundings.
    case warmAtRest
    /// Temperatures are ordinary for what is running.
    case normal
    /// Everything is cool.
    case cool
}

/// A reading of the recent samples: the main cause of heat, the part to name, its temperature,
/// and a level for colour.
public struct ThermalAssessment: Equatable, Sendable {
    public let cause: ThermalCause
    public let source: ThermalSource
    public let celsius: Double
    public let level: LoadLevel
    /// How fast the named part is warming (positive) or cooling (negative), in °C per minute;
    /// nil until the samples cover enough time.
    public let trendPerMinute: Double?
    /// Fan effort 0...1; nil on Macs without fans.
    public let fanFraction: Double?

    // Thresholds, in °C for temperatures and 0...1 for load and fan effort.
    static let coolBelow = 45.0
    static let warmFrom = 60.0
    static let hotFrom = 80.0
    static let veryHotFrom = 95.0
    /// Staying this warm with little running is out of the ordinary.
    static let warmAtRestAttentionFrom = 70.0
    static let busyCPU = 0.5
    static let busyGPU = 0.35
    static let quietCPU = 0.25
    static let quietGPU = 0.15
    static let fansHigh = 0.75
    /// When one part is busy but the other is this much hotter and not idle, both are counted.
    static let alsoWarmerBy = 8.0
    /// Load is averaged over this window, so a single busy sample does not decide the cause.
    static let loadWindow: TimeInterval = 20
    /// The trend is fitted over this window, and only once the samples cover `trendMinimumSpan`.
    static let trendWindow: TimeInterval = 120
    static let trendMinimumSpan: TimeInterval = 45
    /// Falling at least this fast (°C per minute) counts as cooling down.
    static let fallingFaster = -1.0
    /// Anything above this (°C per minute) counts as not falling.
    static let notFalling = -0.3

    /// True when the heat is out of the ordinary and worth a look at the fans: macOS is slowing
    /// down, the cooling cannot keep up, a part is very hot, or the Mac stays warm while idle. A
    /// busy chip running in the 80s is ordinary for Apple silicon and does not count.
    public var needsAttention: Bool {
        switch cause {
        case .throttling, .cannotCool: true
        case .warmAtRest: celsius >= Self.warmAtRestAttentionFrom
        default: celsius >= Self.veryHotFrom
        }
    }

    /// Nil when the newest sample has no temperatures. `samples` are oldest first.
    public static func assess(_ samples: [Snapshot]) -> ThermalAssessment? {
        guard let latest = samples.last, let reading = latest.thermal,
              let hottest = hottestSource(reading) else { return nil }

        let cpu = averageLoad(samples, latest: latest) { $0.cpuUsage }
        let gpu = averageLoad(samples, latest: latest) { $0.gpuUsage ?? 0 }
        let fans = reading.fanFraction
        let quiet = cpu < quietCPU && gpu < quietGPU

        func result(_ cause: ThermalCause, _ source: ThermalSource) -> ThermalAssessment {
            let celsius = reading.celsius(source) ?? hottest.celsius
            return ThermalAssessment(
                cause: cause, source: source, celsius: celsius, level: level(cause: cause, celsius: celsius),
                trendPerMinute: trend(samples, source: source, latest: latest), fanFraction: fans
            )
        }

        if reading.pressure >= .serious { return result(.throttling, hottest.source) }

        let hottestTrend = trend(samples, source: hottest.source, latest: latest)
        let stillWarming = (hottestTrend ?? 0) > 0
        if (fans ?? 0) >= fansHigh, hottest.celsius >= warmFrom, quiet || (hottest.celsius >= hotFrom && stillWarming) {
            return result(.cannotCool, hottest.source)
        }

        let cpuCelsius = reading.celsius(.cpu) ?? 0
        let gpuCelsius = reading.celsius(.gpu) ?? 0
        let cpuBusy = cpu >= busyCPU
        let gpuBusy = gpu >= busyGPU
        // A busy GPU next to a clearly hotter, working CPU (or the reverse) is both at work.
        let cpuAlsoWorking = gpuBusy && cpu >= quietCPU && cpuCelsius >= gpuCelsius + alsoWarmerBy
        let gpuAlsoWorking = cpuBusy && gpu >= quietGPU && gpuCelsius >= cpuCelsius + alsoWarmerBy
        if (cpuBusy && gpuBusy) || cpuAlsoWorking || gpuAlsoWorking {
            return result(.heavyWork, hotter(.cpu, .gpu, in: reading))
        }
        if gpuBusy { return result(.gpuWork, reading.celsius(.gpu) != nil ? .gpu : hottest.source) }
        if cpuBusy { return result(.cpuWork, reading.celsius(.cpu) != nil ? .cpu : hottest.source) }

        if hottest.celsius >= warmFrom {
            if let hottestTrend, hottestTrend <= fallingFaster { return result(.coolingDown, hottest.source) }
            if quiet, (hottestTrend ?? 0) > notFalling { return result(.warmAtRest, hottest.source) }
        }
        return result(hottest.celsius < coolBelow ? .cool : .normal, hottest.source)
    }

    /// The warmest part other than the battery, which only follows the rest; the battery alone
    /// when it is the only sensor.
    static func hottestSource(_ reading: ThermalReading) -> (source: ThermalSource, celsius: Double)? {
        let parts = reading.temperatures.filter { $0.key != .battery }
        let candidates = parts.isEmpty ? reading.temperatures : parts
        return candidates
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .first
            .map { ($0.key, $0.value) }
    }

    static func level(cause: ThermalCause, celsius: Double) -> LoadLevel {
        if cause == .throttling { return .critical }
        let byTemperature: LoadLevel = switch celsius {
        case ..<warmFrom: .low
        case ..<hotFrom: .moderate
        case ..<veryHotFrom: .high
        default: .critical
        }
        if cause == .cannotCool, byTemperature == .low || byTemperature == .moderate { return .high }
        return byTemperature
    }

    private static func hotter(_ a: ThermalSource, _ b: ThermalSource, in reading: ThermalReading) -> ThermalSource {
        switch (reading.celsius(a), reading.celsius(b)) {
        case let (x?, y?): x >= y ? a : b
        case (_?, nil): a
        default: b
        }
    }

    private static func averageLoad(_ samples: [Snapshot], latest: Snapshot, _ value: (Snapshot) -> Double) -> Double {
        let start = latest.timestamp.addingTimeInterval(-loadWindow)
        let recent = samples.filter { $0.timestamp >= start }
        guard !recent.isEmpty else { return value(latest) }
        return recent.map(value).reduce(0, +) / Double(recent.count)
    }

    /// Least-squares slope of the source's temperature over the trend window, in °C per minute.
    static func trend(_ samples: [Snapshot], source: ThermalSource, latest: Snapshot) -> Double? {
        let start = latest.timestamp.addingTimeInterval(-trendWindow)
        let points = samples.compactMap { sample -> (Double, Double)? in
            guard sample.timestamp >= start, let celsius = sample.thermal?.celsius(source) else { return nil }
            return (sample.timestamp.timeIntervalSince(latest.timestamp), celsius)
        }
        guard let first = points.first, let last = points.last, last.0 - first.0 >= trendMinimumSpan else { return nil }
        let count = Double(points.count)
        let meanX = points.map(\.0).reduce(0, +) / count
        let meanY = points.map(\.1).reduce(0, +) / count
        let covariance = points.map { ($0.0 - meanX) * ($0.1 - meanY) }.reduce(0, +)
        let variance = points.map { ($0.0 - meanX) * ($0.0 - meanX) }.reduce(0, +)
        guard variance > 0 else { return nil }
        return covariance / variance * 60
    }
}
