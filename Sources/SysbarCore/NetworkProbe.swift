import Darwin

public struct NetworkTotals: Equatable, Sendable {
    public let received: UInt32
    public let sent: UInt32
}

public enum NetworkProbe {
    /// Cumulative bytes over the Ethernet and Wi-Fi interfaces ("en*"). Tunnel and loopback
    /// interfaces are skipped so VPN traffic is not counted twice. The kernel exposes 32-bit
    /// counters; summing them with wrapping addition keeps deltas correct across wraparound.
    public static func readTotals() -> NetworkTotals? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var received: UInt32 = 0
        var sent: UInt32 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let info = entry.pointee
            if isCountedLink(info), let data = info.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received &+= counters.ifi_ibytes
                sent &+= counters.ifi_obytes
            }
            cursor = info.ifa_next
        }
        return NetworkTotals(received: received, sent: sent)
    }

    private static func isCountedLink(_ info: ifaddrs) -> Bool {
        guard let address = info.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK) else { return false }
        guard info.ifa_flags & UInt32(IFF_UP) != 0 else { return false }
        return String(cString: info.ifa_name).hasPrefix("en")
    }
}
