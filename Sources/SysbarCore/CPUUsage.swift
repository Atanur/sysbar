import Darwin

public struct CPUTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUUsage {
    /// Busy share (0...1) between two tick readings. Wrapping subtraction handles counter overflow.
    public static func fraction(from previous: CPUTicks, to current: CPUTicks) -> Double {
        let user = Double(current.user &- previous.user)
        let system = Double(current.system &- previous.system)
        let nice = Double(current.nice &- previous.nice)
        let idle = Double(current.idle &- previous.idle)
        let busy = user + system + nice
        let total = busy + idle
        return total == 0 ? 0 : busy / total
    }

    public static func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
    }
}
