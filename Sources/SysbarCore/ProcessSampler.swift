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
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    /// Takes the baseline reading; the next `sample()` then covers a clean interval.
    public func prime() {
        _ = sample()
    }

    /// Per-app load since the previous call. Empty on the first call, which has no baseline.
    public func sample() -> [AppUsage] {
        let nanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let current = readCounters()
        let last = previousNanos
        let baseline = previous
        previous = current
        previousNanos = nanos

        guard let last else { return [] }
        return AppUsageCalculator.usage(
            previous: baseline, current: current, seconds: Double(nanos - last) / 1e9, cores: Self.cores
        )
    }

    private func readCounters() -> [Int32: ProcessCounters] {
        let gpu = GPUProbe.clientGPUNanoseconds()
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
            counters[pid] = ProcessCounters(
                group: group(for: pid, start: info.ri_proc_start_abstime),
                cpuNanoseconds: nanoseconds(fromMachTicks: info.ri_user_time &+ info.ri_system_time),
                energyNanojoules: info.ri_energy_nj,
                footprintBytes: info.ri_phys_footprint,
                gpuNanoseconds: gpu[pid] ?? 0
            )
        }
        groupCache = groupCache.filter { live.contains($0.key) }
        return counters
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
