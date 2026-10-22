import Foundation
import IOKit

/// GPU readings from the IORegistry. Both are readable without elevated privileges.
public enum GPUProbe {
    /// Device utilization (0...1) from the accelerator's `PerformanceStatistics`.
    public static func utilization() -> Double? {
        var highest: Double?
        forEachAccelerator { accelerator in
            guard
                let statistics = property(accelerator, "PerformanceStatistics") as? [String: Any],
                let percent = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue
            else { return }
            highest = max(highest ?? 0, percent / 100)
        }
        return highest.map { min($0, 1) }
    }

    /// Accumulated GPU time in nanoseconds per client process, from the accelerator's user clients.
    public static func clientGPUNanoseconds() -> [Int32: UInt64] {
        var totals: [Int32: UInt64] = [:]
        forEachAccelerator { accelerator in
            forEachChild(of: accelerator) { client in
                guard
                    let creator = property(client, "IOUserClientCreator") as? String,
                    let pid = pid(fromClientCreator: creator),
                    let usage = property(client, "AppUsage") as? [[String: Any]]
                else { return }
                let nanoseconds = usage.reduce(UInt64(0)) {
                    $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0)
                }
                totals[pid, default: 0] += nanoseconds
            }
        }
        return totals
    }

    /// Parses the process id out of `IOUserClientCreator`, which reads like "pid 373, logd".
    static func pid(fromClientCreator creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst("pid ".count).prefix { $0.isNumber }
        return Int32(digits)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private static func forEachChild(of parent: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryEntryCreateIterator(parent, kIOServicePlane, options, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var child = IOIteratorNext(iterator)
        while child != 0 {
            body(child)
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
    }
}
