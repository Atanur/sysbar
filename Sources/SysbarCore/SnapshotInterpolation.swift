import Foundation

extension Snapshot {
    /// The reading `fraction` of the way from `from` to `to`, for animating between samples.
    /// Numbers move linearly; states that are not numbers (memory pressure, battery) and values
    /// missing on either side are taken from the newer sample. `fraction` is clamped to 0...1.
    public static func interpolated(from: Snapshot, to: Snapshot, fraction: Double) -> Snapshot {
        let t = min(max(fraction.isFinite ? fraction : 1, 0), 1)
        if t == 1 { return to }

        return Snapshot(
            timestamp: from.timestamp.addingTimeInterval(to.timestamp.timeIntervalSince(from.timestamp) * t),
            cpuUsage: lerp(from.cpuUsage, to.cpuUsage, t),
            memory: MemoryReading(
                usedBytes: lerp(from.memory.usedBytes, to.memory.usedBytes, t),
                totalBytes: to.memory.totalBytes,
                pressure: to.memory.pressure
            ),
            power: lerp(from.power, to.power, t),
            systemPower: lerp(from.systemPower, to.systemPower, t),
            gpuUsage: lerp(from.gpuUsage, to.gpuUsage, t),
            disk: lerp(from.disk, to.disk, t),
            network: lerp(from.network, to.network, t),
            battery: to.battery,
            thermal: to.thermal,
            diskSpace: to.diskSpace,
            networkLink: to.networkLink
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func lerp(_ a: Double?, _ b: Double?, _ t: Double) -> Double? {
        guard let a, let b else { return b }
        return lerp(a, b, t)
    }

    /// Byte counts are unsigned, so the difference is taken in floating point to allow shrinking.
    private static func lerp(_ a: UInt64, _ b: UInt64, _ t: Double) -> UInt64 {
        UInt64(max(lerp(Double(a), Double(b), t), 0).rounded())
    }

    private static func lerp(_ a: IOThroughput?, _ b: IOThroughput?, _ t: Double) -> IOThroughput? {
        guard let a, let b else { return b }
        return IOThroughput(inbound: lerp(a.inbound, b.inbound, t), outbound: lerp(a.outbound, b.outbound, t))
    }

    private static func lerp(_ a: PowerReading?, _ b: PowerReading?, _ t: Double) -> PowerReading? {
        guard let a, let b else { return b }
        return PowerReading(
            cpu: lerp(a.cpu, b.cpu, t), gpu: lerp(a.gpu, b.gpu, t),
            ane: lerp(a.ane, b.ane, t), ram: lerp(a.ram, b.ram, t)
        )
    }
}
