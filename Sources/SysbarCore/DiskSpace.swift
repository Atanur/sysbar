import Foundation

/// How much room is left on a volume.
public struct DiskSpace: Equatable, Sendable {
    public let availableBytes: UInt64
    public let totalBytes: UInt64

    public init(availableBytes: UInt64, totalBytes: UInt64) {
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    /// Below these shares of the volume the room left is worth a second look.
    public static let lowBelow = 0.15
    public static let criticalBelow = 0.05

    public enum Level: Equatable, Sendable {
        case plenty, low, critical
    }

    public var freeFraction: Double {
        totalBytes == 0 ? 0 : min(Double(availableBytes) / Double(totalBytes), 1)
    }

    public var level: Level {
        if freeFraction < Self.criticalBelow { return .critical }
        return freeFraction < Self.lowBelow ? .low : .plenty
    }
}

public enum DiskSpaceProbe {
    /// The room left on a volume as Finder counts it: space macOS can free on its own (caches,
    /// local snapshots) counts as available. One cheap call, made about once a minute.
    public static func read(volume: URL = URL(fileURLWithPath: "/")) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard
            let values = try? volume.resourceValues(forKeys: keys),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        return DiskSpace(availableBytes: UInt64(max(available, 0)), totalBytes: UInt64(total))
    }
}
