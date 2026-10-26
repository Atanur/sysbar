import SystemConfiguration

/// What kind of connection the Mac reaches the network through.
public enum NetworkLink: Equatable, Sendable {
    case wifi, ethernet, other
}

/// Finds the connection the default route uses. Listing the network interfaces to learn their kind
/// takes around 13 ms, so each interface's kind is looked up once and remembered; what is read on
/// every sample is only the name of the primary interface. Use from one queue only.
public final class NetworkLinkProbe {
    private let store = SCDynamicStoreCreate(nil, "Sysbar" as CFString, nil, nil)
    private var kinds: [String: NetworkLink] = [:]

    public init() {}

    /// The connection the default route uses, or nil when the Mac is offline.
    public func primary() -> NetworkLink? {
        guard
            let store,
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
            let name = global["PrimaryInterface"] as? String
        else { return nil }
        if let known = kinds[name] { return known }
        let kind = Self.link(forInterface: name)
        kinds[name] = kind
        return kind
    }

    static func link(forInterface name: String) -> NetworkLink {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let match = interfaces.first { (SCNetworkInterfaceGetBSDName($0) as String?) == name }
        guard let match, let type = SCNetworkInterfaceGetInterfaceType(match) as String? else { return .other }
        if type == (kSCNetworkInterfaceTypeIEEE80211 as String) { return .wifi }
        if type == (kSCNetworkInterfaceTypeEthernet as String) { return .ethernet }
        return .other
    }
}
