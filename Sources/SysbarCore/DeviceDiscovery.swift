import Foundation

/// Devices that could be added, from two lists the Mac already has: Macs that announce Remote Login
/// on the local network (Bonjour `_ssh._tcp`), and the machines in the user's Tailscale network.
/// Nothing is scanned and nothing is connected to; a device found in both is shown once.
public enum DeviceDiscovery {
    /// A Bonjour SSH service on the local network: the computer name and its `.local` host.
    public struct LocalService: Equatable, Sendable {
        public let name: String
        public let host: String

        public init(name: String, host: String) {
            self.name = name
            self.host = DeviceDiscovery.withoutRootDot(host)
        }
    }

    /// A Mac or Linux machine in the Tailscale network.
    public struct TailscalePeer: Equatable, Sendable {
        /// The computer's own name, as Bonjour would show it.
        public let name: String
        /// The MagicDNS name, such as "vps.tail1234.ts.net", without the final dot.
        public let dnsName: String
        public let system: DeviceSetupGuide.System
        /// Its 100.x address, which works wherever Tailscale is connected.
        public let address: String
        public let isOnline: Bool

        /// "vps" from "vps.tail1234.ts.net": the name the Tailscale admin page shows.
        public var machineName: String {
            dnsName.split(separator: ".").first.map(String.init) ?? name
        }
    }

    /// One device to suggest, with every address it was found at.
    public struct Found: Equatable, Identifiable, Sendable {
        public let name: String
        /// Nil when only Bonjour saw it, which does not tell the system.
        public let system: DeviceSetupGuide.System?
        /// Its `.local` name, when it announced SSH on this network.
        public let localHost: String?
        public let tailscale: TailscalePeer?

        public var id: String { DeviceDiscovery.key(name) }

        /// Every address to offer, Tailscale first since it also works away from home.
        public var hosts: [String] { [tailscale?.address, localHost].compactMap { $0 } }

        /// Reachable now: on this network, or online in Tailscale.
        public var isReachable: Bool { localHost != nil || tailscale?.isOnline == true }

        /// Every name it can be reached by, to spot one that is already added.
        var names: [String] {
            [localHost, tailscale?.address, tailscale?.dnsName, tailscale?.machineName].compactMap { $0 }
        }
    }

    /// The Macs and Linux machines in the output of `tailscale status --json`. This Mac is in
    /// "Self", not "Peer", so it is never listed; phones and Windows PCs cannot be monitored.
    public static func tailscalePeers(fromStatusJSON data: Data) -> [TailscalePeer] {
        guard let status = try? JSONDecoder().decode(TailscaleStatus.self, from: data) else { return [] }
        return (status.peers ?? [:]).values.compactMap { node in
            guard let system = system(ofTailscaleOS: node.os),
                  let address = node.addresses?.first(where: { !$0.contains(":") }) else { return nil }
            return TailscalePeer(
                name: node.hostName ?? "", dnsName: withoutRootDot(node.dnsName ?? ""),
                system: system, address: address, isOnline: node.online ?? false
            )
        }
    }

    /// The devices to suggest: the two lists joined by computer name, without this Mac and without
    /// any device whose address or name an added device already uses. Reachable ones come first.
    public static func merge(
        local: [LocalService], tailscale: [TailscalePeer], thisMac: LocalService, added: [String]
    ) -> [Found] {
        let known = Set((added + [thisMac.host]).map { key(withoutRootDot($0)) })
        let services = unique(local.filter { key($0.name) != key(thisMac.name) && key($0.host) != key(thisMac.host) })
        let peersByName = Dictionary(tailscale.map { (key($0.name), $0) }, uniquingKeysWith: { first, _ in first })

        let fromLocal = services.map { service in
            let peer = peersByName[key(service.name)]
            return Found(name: service.name, system: peer?.system, localHost: service.host, tailscale: peer)
        }
        let localNames = Set(services.map { key($0.name) })
        let fromTailscale = tailscale
            .filter { !localNames.contains(key($0.name)) }
            .map { Found(name: $0.name.isEmpty ? $0.machineName : $0.name, system: $0.system, localHost: nil, tailscale: $0) }

        return (fromLocal + fromTailscale)
            .filter { found in !found.names.contains { known.contains(key($0)) } }
            .sorted { ($0.isReachable ? 0 : 1, key($0.name)) < ($1.isReachable ? 0 : 1, key($1.name)) }
    }

    /// Names and hosts compare without case.
    static func key(_ text: String) -> String {
        text.lowercased()
    }

    /// "host.local." and "host.local" are the same host.
    static func withoutRootDot(_ host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    /// A Mac on two interfaces, such as Wi-Fi and Ethernet, is announced twice.
    private static func unique(_ services: [LocalService]) -> [LocalService] {
        var seen = Set<String>()
        return services.filter { seen.insert(key($0.name)).inserted }
    }

    private static func system(ofTailscaleOS os: String?) -> DeviceSetupGuide.System? {
        switch os?.lowercased() {
        case "macos": .mac
        case "linux": .linux
        default: nil
        }
    }

    /// The parts of Tailscale's status that are used.
    private struct TailscaleStatus: Decodable {
        let peers: [String: Node]?

        enum CodingKeys: String, CodingKey {
            case peers = "Peer"
        }

        struct Node: Decodable {
            let hostName: String?
            let dnsName: String?
            let os: String?
            let addresses: [String]?
            let online: Bool?

            enum CodingKeys: String, CodingKey {
                case hostName = "HostName", dnsName = "DNSName", os = "OS", addresses = "TailscaleIPs", online = "Online"
            }
        }
    }
}
