import Darwin
import Foundation

/// Samples per-app CPU, memory, GPU and energy. Only processes the current user may inspect are
/// visible to `proc_pid_rusage`. Stateful: use from one queue only.
public final class ProcessSampler {
    private static let pathBufferSize = 4_096
    private static let cores = ProcessInfo.processInfo.activeProcessorCount

    private var previous: [Int32: ProcessCounters] = [:]
    private var previousNanos: UInt64?
    private var groupCache: [Int32: (start: UInt64, group: String)] = [:]
    /// The last counters `nettop` reported for each process, with when they were read, kept so a
    /// process that closes its sockets does not reappear later with its whole lifetime counted as
    /// one interval.
    private var networkCache: [Int32: (start: UInt64, counters: ByteCounters, nanos: UInt64)] = [:]
    private let readsNetwork: Bool
    private let networkProbe = NettopProbe()
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// `readsNetwork` is false when the apps table has no Network column, so `nettop` is not run
    /// at all.
    public init(readsNetwork: Bool = true) {
        self.readsNetwork = readsNetwork
    }

    /// Takes the baseline reading; the next `sample()` then covers a clean interval.
    public func prime() {
        _ = sample()
    }

    /// Per-app load since the previous call. Empty on the first call, which has no baseline.
    public func sample() -> [AppUsage] {
        let nanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let current = readCounters(at: nanos, previousNanos: previousNanos)
        let last = previousNanos
        let baseline = previous
        previous = current
        previousNanos = nanos

        guard let last else { return [] }
        return AppUsageCalculator.usage(
            previous: baseline, current: current, seconds: Double(nanos - last) / 1e9, cores: Self.cores
        )
    }

    private func readCounters(at nanos: UInt64, previousNanos: UInt64?) -> [Int32: ProcessCounters] {
        let gpu = GPUProbe.clientGPUNanoseconds()
        let network = readsNetwork ? networkProbe.sample() : nil
        var counters: [Int32: ProcessCounters] = [:]
        var live = Set<Int32>()

        for pid in processIdentifiers() where pid > 0 {
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                }
            }
            guard result == 0 else { continue }

            live.insert(pid)
            let start = info.ri_proc_start_abstime
            let reading = networkReading(
                for: pid, start: start, from: network, at: nanos, previousNanos: previousNanos
            )
            counters[pid] = ProcessCounters(
                group: group(for: pid, start: start),
                cpuNanoseconds: nanoseconds(fromMachTicks: info.ri_user_time &+ info.ri_system_time),
                energyNanojoules: info.ri_energy_nj,
                footprintBytes: info.ri_phys_footprint,
                gpuNanoseconds: gpu[pid] ?? 0,
                network: reading.counters,
                networkIsNew: reading.isNew
            )
        }
        groupCache = groupCache.filter { live.contains($0.key) }
        networkCache = networkCache.filter { live.contains($0.key) }
        return counters
    }

    /// A process that is missing from `nettop` has no sockets right now. Keep its last counters so
    /// the next reading continues from there, and treat the first reading of a process, or one
    /// that was missing from the previous sample, as a baseline rather than as one large interval.
    private func networkReading(
        for pid: Int32, start: UInt64, from network: [Int32: ByteCounters]?,
        at nanos: UInt64, previousNanos: UInt64?
    ) -> (counters: ByteCounters?, isNew: Bool) {
        guard let network else { return (nil, false) }
        if let reported = network[pid] {
            let isNew: Bool
            if let cached = networkCache[pid], cached.start == start {
                isNew = cached.nanos < (previousNanos ?? 0)
            } else {
                isNew = true
            }
            networkCache[pid] = (start, reported, nanos)
            return (reported, isNew)
        }
        if let cached = networkCache[pid], cached.start == start {
            return (cached.counters, false)
        }
        return (ByteCounters(received: 0, sent: 0), false)
    }

    private func processIdentifiers() -> [pid_t] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<pid_t>.size + 32)
        let bytesFilled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytesFilled > 0 else { return [] }
        return Array(pids.prefix(Int(bytesFilled) / MemoryLayout<pid_t>.size))
    }

    /// Resolving a path costs a syscall, so the app name is cached per process (keyed by start
    /// time, which changes if the process id is reused).
    private func group(for pid: Int32, start: UInt64) -> String {
        if let cached = groupCache[pid], cached.start == start { return cached.group }

        var path = [CChar](repeating: 0, count: Self.pathBufferSize)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, UInt32(name.count))

        let group = AppGrouping.name(
            forExecutablePath: length > 0 ? String(cString: path) : "",
            fallback: String(cString: name)
        )
        groupCache[pid] = (start, group)
        return group
    }

    private func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return ticks }
        return ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}
