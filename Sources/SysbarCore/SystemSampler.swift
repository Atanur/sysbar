import Foundation

/// Collects one `Snapshot` per call. Stateful (CPU ticks, energy counters): use from one queue only.
public final class SystemSampler {
    private let energy = EnergyMeter()
    private var previousTicks: CPUTicks?
    /// Battery state changes slowly, and reading its registry entry is the costliest probe, so it is
    /// refreshed every few seconds rather than on every sample.
    private static let batteryRefreshNanos: UInt64 = 10_000_000_000
    private var cachedBattery: (info: BatteryInfo?, nanos: UInt64)?
    /// Temperatures move slowly and reading ~60 sensors and the fans costs more than any other
    /// probe here.
    private static let thermalRefreshNanos: UInt64 = 3_000_000_000
    private let thermalProbe = ThermalProbe()
    private let linkProbe = NetworkLinkProbe()
    private var cachedThermal: (reading: ThermalReading, nanos: UInt64)?
    /// Free disk space changes slowly; the connection only when the user changes network (and its
    /// kind is remembered per interface by the probe).
    private static let diskSpaceRefreshNanos: UInt64 = 60_000_000_000
    private static let linkRefreshNanos: UInt64 = 3_000_000_000
    private var cachedDiskSpace: (value: DiskSpace?, nanos: UInt64)?
    private var cachedLink: (value: NetworkLink?, nanos: UInt64)?
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
            thermal: thermal(at: nanos),
            diskSpace: diskSpace(at: nanos),
            networkLink: networkLink(at: nanos)
        )
    }

    private func diskSpace(at nanos: UInt64) -> DiskSpace? {
        if let cached = cachedDiskSpace, nanos - cached.nanos < Self.diskSpaceRefreshNanos { return cached.value }
        let value = DiskSpaceProbe.read()
        cachedDiskSpace = (value, nanos)
        return value
    }

    private func networkLink(at nanos: UInt64) -> NetworkLink? {
        if let cached = cachedLink, nanos - cached.nanos < Self.linkRefreshNanos { return cached.value }
        let value = linkProbe.primary()
        cachedLink = (value, nanos)
        return value
    }

    private func thermal(at nanos: UInt64) -> ThermalReading? {
        if let cached = cachedThermal, nanos - cached.nanos < Self.thermalRefreshNanos { return cached.reading }
        let reading = thermalProbe.read()
        cachedThermal = (reading, nanos)
        return reading.temperatures.isEmpty && reading.fans.isEmpty ? nil : reading
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
