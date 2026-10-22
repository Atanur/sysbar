import Darwin

public struct VMPages: Equatable, Sendable {
    public let `internal`: UInt64
    public let purgeable: UInt64
    public let wired: UInt64
    public let compressed: UInt64

    public init(internal: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.internal = `internal`
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }
}

public enum MemoryProbe {
    /// Activity Monitor's "Memory Used": app memory (internal - purgeable) + wired + compressed.
    public static func usedBytes(pages: VMPages, pageSize: UInt64) -> UInt64 {
        let appPages = pages.internal > pages.purgeable ? pages.internal - pages.purgeable : 0
        return (appPages + pages.wired + pages.compressed) * pageSize
    }

    public static func read() -> MemoryReading? {
        guard let pages = readPages(), let total = sysctlValue("hw.memsize", as: UInt64.self) else { return nil }
        let level = sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self) ?? 1
        return MemoryReading(
            usedBytes: usedBytes(pages: pages, pageSize: UInt64(getpagesize())),
            totalBytes: total,
            pressure: MemoryPressure(kernelLevel: level)
        )
    }

    private static func readPages() -> VMPages? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return VMPages(
            internal: UInt64(stats.internal_page_count),
            purgeable: UInt64(stats.purgeable_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count)
        )
    }

    private static func sysctlValue<T: FixedWidthInteger>(_ name: String, as type: T.Type) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
