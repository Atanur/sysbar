import SystemConfiguration

/// What kind of connection the Mac reaches the network through.
public enum NetworkLink: Equatable, Sendable {
    case wifi, ethernet, other
}

public enum NetworkLinkProbe {
    /// The connection the default route uses, or nil when the Mac is offline.
    public static func primary() -> NetworkLink? {
        guard
            let store = SCDynamicStoreCreate(nil, "Sysbar" as CFString, nil, nil),
            let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
            let name = global["PrimaryInterface"] as? String
        else { return nil }
        return link(forInterface: name)
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
