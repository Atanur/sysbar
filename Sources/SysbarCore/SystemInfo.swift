import Darwin
import Foundation
import IOKit

/// Static facts about this Mac, shown on the settings window's general page.
public struct SystemInfo: Equatable, Sendable {
    public let chip: String
    /// The name Apple sells the machine under, e.g. "MacBook Pro (14-inch, 2021)". Nil when the
    /// firmware does not report one; `modelIdentifier` ("MacBookPro18,3") is always there.
    public let modelName: String?
    public let modelIdentifier: String
    public let osVersion: String
    public let memoryBytes: UInt64
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let logicalCores: Int
    public let diskTotalBytes: UInt64?
    public let diskFreeBytes: UInt64?
    public let uptime: TimeInterval
}

public enum SystemInfoProbe {
    public static func read() -> SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let volume = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        )
        return SystemInfo(
            chip: string("machdep.cpu.brand_string") ?? L("Unknown"),
            modelName: marketingName(),
            modelIdentifier: string("hw.model") ?? L("Unknown"),
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion)",
            memoryBytes: integer("hw.memsize", as: UInt64.self) ?? 0,
            performanceCores: integer("hw.perflevel0.physicalcpu", as: Int32.self).map(Int.init) ?? 0,
            efficiencyCores: integer("hw.perflevel1.physicalcpu", as: Int32.self).map(Int.init) ?? 0,
            logicalCores: ProcessInfo.processInfo.activeProcessorCount,
            diskTotalBytes: volume?.volumeTotalCapacity.map(UInt64.init),
            diskFreeBytes: volume?.volumeAvailableCapacityForImportantUsage.map(UInt64.init),
            uptime: uptime()
        )
    }

    /// Apple silicon firmware publishes the marketing name as the `product-name` property of a
    /// platform device in the IORegistry, as a NUL-terminated UTF-8 string.
    private static func marketingName() -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let data = IORegistryEntryCreateCFProperty(service, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data {
                let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Time since boot including sleep, like the uptime other tools report.
    private static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }

    private static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func integer<T: FixedWidthInteger>(_ name: String, as type: T.Type) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
