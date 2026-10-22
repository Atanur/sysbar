import Foundation
import IOKit

public struct DiskTotals: Equatable, Sendable {
    public let read: UInt64
    public let written: UInt64
}

public enum DiskProbe {
    /// Cumulative bytes read and written, summed over every block storage driver.
    public static func readTotals() -> DiskTotals? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)
            if let statistics = property?.takeRetainedValue() as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return DiskTotals(read: read, written: written)
    }
}
