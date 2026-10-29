import Foundation

/// Cumulative per-process counters at one instant.
public struct ProcessCounters: Equatable, Sendable {
    public let group: String
    public let cpuNanoseconds: UInt64
    public let energyNanojoules: UInt64
    public let footprintBytes: UInt64
    public let gpuNanoseconds: UInt64
    /// Cumulative bytes this process has received and sent, or nil when `nettop` could not be
    /// read on this sample.
    public let network: ByteCounters?
    /// True when this is the first network reading for the process. It is a baseline, not a
    /// delta: the counters include bytes from before Sysbar started watching.
    public let networkIsNew: Bool

    public init(
        group: String, cpuNanoseconds: UInt64, energyNanojoules: UInt64,
        footprintBytes: UInt64, gpuNanoseconds: UInt64, network: ByteCounters? = nil,
        networkIsNew: Bool = false
    ) {
        self.group = group
        self.cpuNanoseconds = cpuNanoseconds
        self.energyNanojoules = energyNanojoules
        self.footprintBytes = footprintBytes
        self.gpuNanoseconds = gpuNanoseconds
        self.network = network
        self.networkIsNew = networkIsNew
    }
}

/// One app's current load, summed over all of its processes.
public struct AppUsage: Equatable, Sendable {
    public let name: String
    /// Share of the whole machine, all cores together, as the CPU card shows it.
    public let cpu: Double
    public let memoryBytes: UInt64
    /// Share of GPU time.
    public let gpu: Double
    public let powerWatts: Double
    /// Bytes per second, or nil when per-app network reading is unavailable.
    public let networkInbound: Double?
    public let networkOutbound: Double?

    public init(
        name: String, cpu: Double, memoryBytes: UInt64, gpu: Double, powerWatts: Double,
        networkInbound: Double? = nil, networkOutbound: Double? = nil
    ) {
        self.name = name
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.gpu = gpu
        self.powerWatts = powerWatts
        self.networkInbound = networkInbound
        self.networkOutbound = networkOutbound
    }

    /// Both directions together, which is what the table's compact Network column shows.
    public var networkTotal: Double? {
        guard let networkInbound, let networkOutbound else { return nil }
        return networkInbound + networkOutbound
    }
}

public enum AppSortKey: String, CaseIterable, Sendable {
    case cpu, memory, gpu, power, network

    func value(of usage: AppUsage) -> Double {
        switch self {
        case .cpu: usage.cpu
        case .memory: Double(usage.memoryBytes)
        case .gpu: usage.gpu
        case .power: usage.powerWatts
        case .network: usage.networkTotal ?? 0
        }
    }
}

public enum AppGrouping {
    /// Names the app a process belongs to: the first ".app" bundle in its path, so helper processes
    /// fold into their parent app. Plain executables use their file name.
    public static func name(forExecutablePath path: String, fallback: String) -> String {
        guard !path.isEmpty else { return fallback }
        let components = path.split(separator: "/")
        if let bundle = components.first(where: { $0.hasSuffix(".app") }) {
            return String(bundle.dropLast(".app".count))
        }
        return components.last.map(String.init) ?? fallback
    }
}

public enum AppUsageCalculator {
    private static let nanosecondsToSeconds = 1e-9

    /// Per-app load over `seconds`. CPU is divided over the `cores` so the apps add up to no more
    /// than the CPU card. Processes without a previous reading (just started) contribute memory
    /// only; counters that went backwards (process id reused) count as zero.
    public static func usage(
        previous: [Int32: ProcessCounters], current: [Int32: ProcessCounters], seconds: Double, cores: Int
    ) -> [AppUsage] {
        let coreCount = Double(max(cores, 1))
        let perProcess = current.map { pid, now in
            let before = previous[pid]
            let network = now.network
            return AppUsage(
                name: now.group,
                cpu: rate(before?.cpuNanoseconds, now.cpuNanoseconds, seconds) / coreCount,
                memoryBytes: now.footprintBytes,
                gpu: rate(before?.gpuNanoseconds, now.gpuNanoseconds, seconds),
                powerWatts: rate(before?.energyNanojoules, now.energyNanojoules, seconds),
                networkInbound: network.map {
                    if now.networkIsNew { return 0 }
                    return CounterRate.perSecond(
                        previous: before?.network?.received ?? $0.received, current: $0.received,
                        seconds: seconds
                    )
                },
                networkOutbound: network.map {
                    if now.networkIsNew { return 0 }
                    return CounterRate.perSecond(
                        previous: before?.network?.sent ?? $0.sent, current: $0.sent, seconds: seconds
                    )
                }
            )
        }
        return Dictionary(grouping: perProcess, by: \.name).map { name, items in
            let inbound = items.compactMap(\.networkInbound)
            let outbound = items.compactMap(\.networkOutbound)
            return AppUsage(
                name: name,
                cpu: items.map(\.cpu).reduce(0, +),
                memoryBytes: items.map(\.memoryBytes).reduce(0, +),
                gpu: items.map(\.gpu).reduce(0, +),
                powerWatts: items.map(\.powerWatts).reduce(0, +),
                networkInbound: inbound.isEmpty ? nil : inbound.reduce(0, +),
                networkOutbound: outbound.isEmpty ? nil : outbound.reduce(0, +)
            )
        }
    }

    /// Highest first by `key`; ties break alphabetically so the order is stable.
    public static func top(_ usages: [AppUsage], by key: AppSortKey, limit: Int) -> [AppUsage] {
        let ordered = usages.sorted { lhs, rhs in
            let (left, right) = (key.value(of: lhs), key.value(of: rhs))
            return left != right ? left > right : lhs.name < rhs.name
        }
        return Array(ordered.prefix(limit))
    }

    private static func rate(_ previous: UInt64?, _ current: UInt64, _ seconds: Double) -> Double {
        guard let previous, seconds > 0, current >= previous else { return 0 }
        return Double(current - previous) * nanosecondsToSeconds / seconds
    }
}
