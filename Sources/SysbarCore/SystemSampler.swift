import Foundation

/// Collects one `Snapshot` per call. Stateful (CPU ticks, energy counters): use from one queue only.
public final class SystemSampler {
    private let energy = EnergyMeter()
    private var previousTicks: CPUTicks?
    /// Battery state changes slowly, and reading its registry entry is the costliest probe, so it is
    /// refreshed every few seconds rather than on every sample.
    private static let batteryRefreshNanos: UInt64 = 10_000_000_000
    private var cachedBattery: (info: BatteryInfo?, nanos: UInt64)?
    /// Temperature moves slowly and reading ~30 sensors costs more than any other probe here.
    private static let temperatureRefreshNanos: UInt64 = 3_000_000_000
    private let temperatureProbe = CPUTemperatureProbe()
    private var cachedTemperature: (celsius: Double?, nanos: UInt64)?
    private var previousDisk: (totals: DiskTotals, nanos: UInt64)?
    private var previousNetwork: (totals: NetworkTotals, nanos: UInt64)?

    public init() {}

    /// Records baselines so the next `sample()` covers a clean interval.
    public func prime() {
        _ = sample()
    }

    /// Dumps raw IOReport energy channels for the last interval (used by `--probe`).
    public func describeEnergyChannels() -> [String] {
        energy?.describeChannels() ?? []
    }

    public func sample(at date: Date = Date()) -> Snapshot {
        let ticks = CPUUsage.readTicks()
        let cpu = zip(previousTicks, ticks).map { CPUUsage.fraction(from: $0, to: $1) } ?? 0
        previousTicks = ticks

        let nanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        return Snapshot(
            timestamp: date,
            cpuUsage: cpu,
            memory: MemoryProbe.read() ?? MemoryReading(usedBytes: 0, totalBytes: 0, pressure: .normal),
            power: energy?.read(),
            systemPower: SystemPower.watts(),
            gpuUsage: GPUProbe.utilization(),
            disk: diskThroughput(at: nanos),
            network: networkThroughput(at: nanos),
            battery: battery(at: nanos),
            cpuTemperature: temperature(at: nanos)
        )
    }

    private func temperature(at nanos: UInt64) -> Double? {
        if let cached = cachedTemperature, nanos - cached.nanos < Self.temperatureRefreshNanos { return cached.celsius }
        let celsius = temperatureProbe.read()
        cachedTemperature = (celsius, nanos)
        return celsius
    }

    private func battery(at nanos: UInt64) -> BatteryInfo? {
        if let cached = cachedBattery, nanos - cached.nanos < Self.batteryRefreshNanos { return cached.info }
        let info = BatteryProbe.read()
        cachedBattery = (info, nanos)
        return info
    }

    private func diskThroughput(at nanos: UInt64) -> IOThroughput? {
        guard let totals = DiskProbe.readTotals() else { return nil }
        let last = previousDisk
        previousDisk = (totals, nanos)
        guard let last else { return nil }

        let seconds = Double(nanos - last.nanos) / 1e9
        return IOThroughput(
            inbound: CounterRate.perSecond(previous: last.totals.read, current: totals.read, seconds: seconds),
            outbound: CounterRate.perSecond(previous: last.totals.written, current: totals.written, seconds: seconds)
        )
    }

    private func networkThroughput(at nanos: UInt64) -> IOThroughput? {
        guard let totals = NetworkProbe.readTotals() else { return nil }
        let last = previousNetwork
        previousNetwork = (totals, nanos)
        guard let last else { return nil }

        let seconds = Double(nanos - last.nanos) / 1e9
        return IOThroughput(
            inbound: CounterRate.perSecond32(previous: last.totals.received, current: totals.received, seconds: seconds),
            outbound: CounterRate.perSecond32(previous: last.totals.sent, current: totals.sent, seconds: seconds)
        )
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
