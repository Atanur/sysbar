import CSystemBridge
import Darwin
import Foundation

public enum EnergyComponent: Equatable, Sendable {
    case cpu, gpu, ane, ram
}

public enum EnergyChannel {
    /// Maps an IOReport "Energy Model" channel name to a component. Sub-channels such as
    /// "GPU SRAM0" are ignored so they are not double counted.
    public static func component(forChannel name: String) -> EnergyComponent? {
        if name == "GPU Energy" { return .gpu }
        if name.hasSuffix("CPU Energy") { return .cpu }
        if name.hasPrefix("ANE") { return .ane }
        if name.hasPrefix("DRAM") { return .ram }
        return nil
    }

    public static func joules(value: Int64, unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": return Double(value) * 1e-3
        case "uJ", "µJ": return Double(value) * 1e-6
        case "nJ": return Double(value) * 1e-9
        default: return nil
        }
    }
}

struct ChannelDelta {
    let name: String
    let unit: String
    let value: Int64
}

/// Reads CPU/GPU/ANE/RAM energy counters through IOReport and converts deltas to watts.
/// Not thread safe: call `read()` from a single queue.
public final class EnergyMeter {
    private let subscription: IOReportSubscriptionRef
    private let subscribed: CFMutableDictionary
    private var previous: (sample: CFDictionary, nanos: UInt64)?

    public init?() {
        guard let channels = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0) else { return nil }
        Self.keepOnlyUsedChannels(in: channels)
        var subscribedOut: Unmanaged<CFMutableDictionary>?
        guard
            let subscription = IOReportCreateSubscription(nil, channels, &subscribedOut, 0, nil),
            let subscribed = subscribedOut?.takeUnretainedValue()
        else { return nil }
        self.subscription = subscription
        self.subscribed = subscribed
    }

    /// The Energy Model group lists hundreds of per-core and per-rail channels. Subscribing only to
    /// the few we map to a component keeps each sample (and its parsing) tiny.
    private static func keepOnlyUsedChannels(in channels: CFMutableDictionary) {
        let dictionary = channels as NSMutableDictionary
        guard let all = dictionary["IOReportChannels"] as? [NSDictionary] else { return }
        let used = all.filter { item in
            guard let name = IOReportChannelGetChannelName(item as CFDictionary) as String? else { return false }
            return EnergyChannel.component(forChannel: name) != nil
        }
        if !used.isEmpty { dictionary["IOReportChannels"] = used }
    }

    /// Average power since the previous call. Returns nil on the first call or on failure.
    public func read() -> PowerReading? {
        guard let (deltas, seconds) = nextDeltas(), seconds > 0 else { return nil }

        var watts: [EnergyComponent: Double] = [:]
        for delta in deltas {
            guard
                let component = EnergyChannel.component(forChannel: delta.name),
                let joules = EnergyChannel.joules(value: delta.value, unit: delta.unit)
            else { continue }
            watts[component, default: 0] += joules / seconds
        }
        // On recent macOS the CPU and DRAM counters stay frozen for non-root clients and read
        // exactly 0, so a zero there means "no data", not "idle". GPU and ANE counters are live.
        return PowerReading(
            cpu: watts[.cpu].flatMap { $0 > 0 ? $0 : nil }, gpu: watts[.gpu] ?? 0,
            ane: watts[.ane] ?? 0, ram: watts[.ram].flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// Human-readable channel dump (name, unit, raw delta, watts) used by `--probe`.
    public func describeChannels() -> [String] {
        guard let (deltas, seconds) = nextDeltas(), seconds > 0 else { return [] }
        return deltas.map { delta in
            let watts = EnergyChannel.joules(value: delta.value, unit: delta.unit).map { $0 / seconds }
            let component = EnergyChannel.component(forChannel: delta.name).map { "\($0)" } ?? "-"
            return "\(delta.name)\t[\(delta.unit)]\t\(delta.value)\t\(watts.map { String(format: "%.3f W", $0) } ?? "?")\t→ \(component)"
        }
    }

    private func nextDeltas() -> ([ChannelDelta], Double)? {
        let nanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        guard let current = IOReportCreateSamples(subscription, subscribed, nil) else { return nil }
        let last = previous
        previous = (current, nanos)
        guard let last, let delta = IOReportCreateSamplesDelta(last.sample, current, nil) else { return nil }

        let channels = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] ?? []
        let deltas: [ChannelDelta] = channels.compactMap { item in
            let channel = item as CFDictionary
            guard let name = IOReportChannelGetChannelName(channel) as String? else { return nil }
            let unit = (IOReportChannelGetUnitLabel(channel) as String?) ?? ""
            return ChannelDelta(name: name, unit: unit, value: IOReportSimpleGetIntegerValue(channel, 0))
        }
        return (deltas, Double(nanos - last.nanos) / 1e9)
    }
}
