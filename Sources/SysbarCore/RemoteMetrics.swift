import Foundation

public enum RemoteOS: Equatable, Sendable {
    case linux, macOS, other
}

/// Cumulative CPU time from `/proc/stat`, folded into busy and idle.
public struct LinuxCPUTicks: Equatable, Sendable {
    public let busy: UInt64
    public let idle: UInt64
}

/// Cumulative byte counters. Network: received/sent. Disk: read/written.
public struct ByteCounters: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64
}

public struct LoadAverage: Equatable, Sendable {
    public let one: Double
    public let five: Double
    public let fifteen: Double
}

public struct RemoteProcess: Equatable, Sendable {
    public let name: String
    /// Share of a single core.
    public let cpu: Double
    public let memoryBytes: UInt64
}

/// One parsed run of the remote script, before any rates are computed.
public struct RemoteRawSample: Equatable, Sendable {
    public var os: RemoteOS
    public var cores = 0
    public var linuxTicks: LinuxCPUTicks?
    /// macOS reports CPU usage directly rather than as counters.
    public var directCPUUsage: Double?
    public var memoryTotalBytes: UInt64?
    public var memoryUsedBytes: UInt64?
    public var load: LoadAverage?
    public var uptime: TimeInterval?
    public var network: ByteCounters?
    public var disk: ByteCounters?
    public var gpuUsage: Double?
    /// CPU temperature in °C, when the machine exposes a sensor (most virtual servers do not).
    public var cpuTemperature: Double?
    public var processes: [RemoteProcess] = []
}

/// Reads the `key=value` lines printed by `RemoteScript`. Fields that are missing or unreadable
/// become nil rather than failing the whole sample.
public enum RemoteMetricsParser {
    /// The script sends the eight busiest apps by CPU and the eight largest by memory, so the table
    /// is right whichever column it is sorted by.
    private static let maxProcesses = 16
    /// Tools the script itself runs; they would otherwise show up as busy processes.
    private static let scriptToolNames: Set<String> = [
        "ps", "sh", "top", "awk", "sed", "sort", "head", "tail", "grep", "tr", "netstat", "vm_stat", "sysctl", "uname",
    ]

    public static func parse(_ output: String) -> RemoteRawSample? {
        var fields: [String: [String]] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            fields[key, default: []].append(String(line[line.index(after: equals)...]))
        }
        guard let osName = fields["os"]?.first else { return nil }

        var sample = RemoteRawSample(os: os(named: osName))
        sample.cores = fields["cores"]?.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        sample.linuxTicks = fields["cpu"]?.first.flatMap(ticks)
        sample.directCPUUsage = fields["cpuline"]?.first.flatMap(usage(fromTopLine:))
        applyMemory(from: fields, to: &sample)
        sample.load = fields["load"]?.first.flatMap(loadAverage)
        sample.uptime = uptime(from: fields)
        sample.network = fields["net"]?.first.flatMap(counters)
        sample.disk = fields["disk"]?.first.flatMap(counters)
        sample.gpuUsage = fields["gpu"]?.first.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .map { min(max($0 / 100, 0), 1) }
        sample.cpuTemperature = fields["temp"]?.first.flatMap(temperature)
        sample.processes = Array((fields["proc"] ?? []).compactMap(process).prefix(maxProcesses))
        return sample
    }

    private static func os(named name: String) -> RemoteOS {
        switch name.trimmingCharacters(in: .whitespaces) {
        case "Linux": .linux
        case "Darwin": .macOS
        default: .other
        }
    }

    private static func words(_ value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Linux reports millidegrees; anything implausible is treated as no reading.
    private static func temperature(_ value: String) -> Double? {
        guard let raw = Double(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        let celsius = raw > 1_000 ? raw / 1_000 : raw
        return (1.0...130.0).contains(celsius) ? celsius : nil
    }

    private static func ticks(_ value: String) -> LinuxCPUTicks? {
        let numbers = words(value).compactMap { UInt64($0) }
        guard numbers.count >= 4 else { return nil }
        func at(_ index: Int) -> UInt64 { index < numbers.count ? numbers[index] : 0 }
        // user nice system idle iowait irq softirq steal
        let busy = at(0) + at(1) + at(2) + at(5) + at(6) + at(7)
        return LinuxCPUTicks(busy: busy, idle: at(3) + at(4))
    }

    private static func usage(fromTopLine line: String) -> Double? {
        guard let range = line.range(of: #"[0-9]+(?:\.[0-9]+)?(?=% idle)"#, options: .regularExpression),
              let idle = Double(line[range])
        else { return nil }
        return min(max((100 - idle) / 100, 0), 1)
    }

    private static func loadAverage(_ value: String) -> LoadAverage? {
        let numbers = words(value).compactMap { Double($0) }
        guard numbers.count >= 3 else { return nil }
        return LoadAverage(one: numbers[0], five: numbers[1], fifteen: numbers[2])
    }

    private static func counters(_ value: String) -> ByteCounters? {
        let numbers = words(value).compactMap { UInt64($0) }
        guard numbers.count >= 2 else { return nil }
        return ByteCounters(received: numbers[0], sent: numbers[1])
    }

    private static func uptime(from fields: [String: [String]]) -> TimeInterval? {
        if let seconds = fields["uptime"]?.first.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return seconds
        }
        guard
            let boot = fields["boottime"]?.first.flatMap({ UInt64($0.trimmingCharacters(in: .whitespaces)) }),
            let now = fields["now"]?.first.flatMap({ UInt64($0.trimmingCharacters(in: .whitespaces)) }),
            now >= boot
        else { return nil }
        return TimeInterval(now - boot)
    }

    private static func process(_ value: String) -> RemoteProcess? {
        // "<cpu %> <rss KB> <name>": the name goes last because `ps` truncates columns in the middle
        // of a line but not the final one, and names may contain spaces.
        let tokens = words(value)
        guard tokens.count >= 3, let percent = Double(tokens[0]), let rssKilobytes = UInt64(tokens[1]) else { return nil }
        let name = tokens.dropFirst(2).joined(separator: " ")
        guard !name.isEmpty, !scriptToolNames.contains(name) else { return nil }
        return RemoteProcess(name: name, cpu: percent / 100, memoryBytes: rssKilobytes * 1_024)
    }

    // MARK: Memory

    private static func applyMemory(from fields: [String: [String]], to sample: inout RemoteRawSample) {
        if let numbers = fields["mem"]?.first.map({ words($0).compactMap { UInt64($0) } }), numbers.count >= 2,
           numbers[0] >= numbers[1] {
            sample.memoryTotalBytes = numbers[0] * 1_024
            sample.memoryUsedBytes = (numbers[0] - numbers[1]) * 1_024
            return
        }
        guard let total = fields["memtotal"]?.first.flatMap({ UInt64($0.trimmingCharacters(in: .whitespaces)) }) else { return }
        sample.memoryTotalBytes = total
        sample.memoryUsedBytes = macUsedBytes(vmLines: fields["vm"] ?? [])
    }

    /// Activity Monitor's "Memory Used": app memory (anonymous - purgeable) + wired + compressed.
    private static func macUsedBytes(vmLines: [String]) -> UInt64? {
        guard
            let header = vmLines.first(where: { $0.contains("page size of") }),
            let sizeRange = header.range(of: #"(?<=page size of )[0-9]+"#, options: .regularExpression),
            let pageSize = UInt64(header[sizeRange]),
            let anonymous = pages("Anonymous pages", in: vmLines),
            let wired = pages("Pages wired down", in: vmLines),
            let compressed = pages("Pages occupied by compressor", in: vmLines)
        else { return nil }
        let purgeable = pages("Pages purgeable", in: vmLines) ?? 0
        let app = anonymous > purgeable ? anonymous - purgeable : 0
        return (app + wired + compressed) * pageSize
    }

    private static func pages(_ key: String, in lines: [String]) -> UInt64? {
        guard let line = lines.first(where: { $0.hasPrefix(key + ":") }) else { return nil }
        let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        return UInt64(value.hasSuffix(".") ? String(value.dropLast()) : value)
    }
}

public struct RemoteMemory: Equatable, Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public var fraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

/// What the popover shows for a remote machine at one instant.
public struct RemoteSnapshot: Equatable, Sendable {
    public let timestamp: Date
    public let os: RemoteOS
    public let cores: Int
    public let cpuUsage: Double?
    public let memory: RemoteMemory?
    public let load: LoadAverage?
    public let uptime: TimeInterval?
    public let network: IOThroughput?
    public let disk: IOThroughput?
    /// True when the machine reports disk counters at all. The rate itself needs two samples, so
    /// `disk` is nil on the first one; this lets the disk card be offered from the start.
    public let reportsDisk: Bool
    public let gpuUsage: Double?
    public let cpuTemperature: Double?
    public let processes: [RemoteProcess]

    /// One-minute load per core: 1 means every core is busy on average.
    public var loadFraction: Double? {
        guard let load, cores > 0 else { return nil }
        return load.one / Double(cores)
    }
}

/// The cards a remote machine can show, in display order. Each device keeps its own choice.
public enum RemoteCard: String, CaseIterable, Sendable {
    case cpu, memory, load, network, disk, gpu

    /// Cards that have something to show for these samples. Disk and GPU exist only on machines
    /// that report them (Linux servers report disk, those with an NVIDIA card report GPU).
    public static func available(in samples: [RemoteSnapshot]) -> [RemoteCard] {
        allCases.filter { card in
            switch card {
            case .disk: samples.contains { $0.reportsDisk }
            case .gpu: samples.contains { $0.gpuUsage != nil }
            case .cpu, .memory, .load, .network: true
            }
        }
    }

    /// The chosen cards that can actually be shown, in display order.
    public static func visible(chosen: [RemoteCard], available: [RemoteCard]) -> [RemoteCard] {
        allCases.filter { chosen.contains($0) && available.contains($0) }
    }
}

/// Turns successive raw samples into snapshots, computing the values that need a previous sample:
/// Linux CPU usage and the network and disk rates. Use one tracker per connection.
public struct RemoteTracker {
    private var previousTicks: LinuxCPUTicks?
    private var previousNetwork: (counters: ByteCounters, nanos: UInt64)?
    private var previousDisk: (counters: ByteCounters, nanos: UInt64)?

    public init() {}

    public mutating func ingest(_ raw: RemoteRawSample, atNanos nanos: UInt64, date: Date) -> RemoteSnapshot {
        let cpu = raw.directCPUUsage ?? linuxUsage(raw.linuxTicks)
        let network = rate(raw.network, nanos: nanos, previous: &previousNetwork)
        let disk = rate(raw.disk, nanos: nanos, previous: &previousDisk)

        var memory: RemoteMemory?
        if let used = raw.memoryUsedBytes, let total = raw.memoryTotalBytes {
            memory = RemoteMemory(usedBytes: used, totalBytes: total)
        }
        return RemoteSnapshot(
            timestamp: date, os: raw.os, cores: raw.cores, cpuUsage: cpu, memory: memory, load: raw.load,
            uptime: raw.uptime, network: network, disk: disk, reportsDisk: raw.disk != nil,
            gpuUsage: raw.gpuUsage, cpuTemperature: raw.cpuTemperature, processes: raw.processes
        )
    }

    private mutating func linuxUsage(_ ticks: LinuxCPUTicks?) -> Double? {
        guard let ticks else { return nil }
        defer { previousTicks = ticks }
        guard let previous = previousTicks, ticks.busy >= previous.busy, ticks.idle >= previous.idle else { return nil }
        let busy = Double(ticks.busy - previous.busy)
        let total = busy + Double(ticks.idle - previous.idle)
        return total > 0 ? busy / total : nil
    }

    private func rate(
        _ current: ByteCounters?, nanos: UInt64, previous: inout (counters: ByteCounters, nanos: UInt64)?
    ) -> IOThroughput? {
        guard let current else { return nil }
        let last = previous
        previous = (current, nanos)
        guard let last, nanos > last.nanos else { return nil }

        let seconds = Double(nanos - last.nanos) / 1e9
        return IOThroughput(
            inbound: CounterRate.perSecond(previous: last.counters.received, current: current.received, seconds: seconds),
            outbound: CounterRate.perSecond(previous: last.counters.sent, current: current.sent, seconds: seconds)
        )
    }
}
