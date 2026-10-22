import Foundation

/// How long a remote device keeps being sampled after the popover closes, so its history keeps
/// growing and is still there when the popover opens again. Stored as "off", "always" or a number
/// of minutes.
public enum KeepMonitoring: Equatable, Hashable, Sendable {
    case off
    case minutes(Int)
    case always

    public static let `default` = KeepMonitoring.minutes(5)
    public static let choices: [KeepMonitoring] = [.off, .minutes(1), .minutes(5), .minutes(15), .minutes(60), .always]

    /// Seconds to keep going after closing; nil means until the app quits or another device is chosen.
    public var seconds: TimeInterval? {
        switch self {
        case .off: 0
        case .minutes(let minutes): TimeInterval(minutes * 60)
        case .always: nil
        }
    }

    var storedValue: String {
        switch self {
        case .off: "off"
        case .always: "always"
        case .minutes(let minutes): String(minutes)
        }
    }

    /// Anything that is not one of the offered choices falls back to the default.
    init(storedValue: String?) {
        let parsed: KeepMonitoring? = switch storedValue {
        case "off": .off
        case "always": .always
        default: storedValue.flatMap(Int.init).map(KeepMonitoring.minutes)
        }
        self = parsed.flatMap { Self.choices.contains($0) ? $0 : nil } ?? .default
    }
}

/// A machine reachable over SSH. It holds no secrets: authentication uses the user's own keys or
/// ssh-agent, and the identity is only a path.
public struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// A hostname, IP address, or an alias from `~/.ssh/config`.
    public var host: String
    public var user: String
    public var port: Int?
    public var identityFile: String
    /// Cards shown for this device, in display order. May be empty.
    public var cards: [RemoteCard]
    /// Seconds between samples while this device is shown, within `SamplingInterval.remoteRange`.
    public var interval: TimeInterval
    public var keepMonitoring: KeepMonitoring

    public init(
        id: UUID = UUID(), name: String, host: String, user: String, port: Int?, identityFile: String,
        cards: [RemoteCard] = RemoteCard.allCases, interval: TimeInterval = SamplingInterval.remoteDefaultSeconds,
        keepMonitoring: KeepMonitoring = .default
    ) {
        self.keepMonitoring = keepMonitoring
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.cards = cards
        self.interval = SamplingInterval.normalizedRemote(interval)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, user, port, identityFile, cards, interval, keepMonitoring
    }

    /// Devices saved before cards could be chosen have no `cards` entry and show all of them. Cards
    /// are stored as plain strings, so an unknown one is dropped instead of failing the whole device.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        user = try container.decode(String.self, forKey: .user)
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        identityFile = try container.decode(String.self, forKey: .identityFile)
        let stored = try container.decodeIfPresent([String].self, forKey: .cards)
        cards = OrderedSelection.ordered(fromStored: stored) ?? RemoteCard.allCases
        // Older devices have no interval; stored values are clamped so an edited file cannot make
        // Sysbar poll a server faster than allowed.
        interval = SamplingInterval.normalizedRemote(try container.decodeIfPresent(Double.self, forKey: .interval) ?? 0)
        keepMonitoring = KeepMonitoring(storedValue: try? container.decodeIfPresent(String.self, forKey: .keepMonitoring))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(user, forKey: .user)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(identityFile, forKey: .identityFile)
        try container.encode(OrderedSelection.storedValue(of: cards), forKey: .cards)
        try container.encode(interval, forKey: .interval)
        try container.encode(keepMonitoring.storedValue, forKey: .keepMonitoring)
    }

    public enum Problem: Equatable, Sendable {
        case emptyName, invalidHost, invalidUser, invalidPort, invalidIdentityFile
    }

    /// Everything wrong with the entered values; empty when the device is usable. Hosts and users
    /// may not start with "-", so they can never be read as ssh options.
    public var problems: [Problem] {
        var found: [Problem] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.emptyName) }
        if !Self.isValid(host, allowed: Self.hostCharacters, allowEmpty: false) { found.append(.invalidHost) }
        if !Self.isValid(user, allowed: Self.userCharacters, allowEmpty: true) { found.append(.invalidUser) }
        if let port, !(1...65_535).contains(port) { found.append(.invalidPort) }
        if !Self.isValidIdentity(identityFile) { found.append(.invalidIdentityFile) }
        return found
    }

    /// "user@host:port" with the parts that are set.
    public var address: String {
        let base = user.isEmpty ? host : "\(user)@\(host)"
        return port.map { "\(base):\($0)" } ?? base
    }

    private static let userCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    private static let hostCharacters = userCharacters.union(CharacterSet(charactersIn: ":"))

    private static func isValid(_ value: String, allowed: CharacterSet, allowEmpty: Bool) -> Bool {
        if value.isEmpty { return allowEmpty }
        guard value.first != "-" else { return false }
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isValidIdentity(_ path: String) -> Bool {
        if path.isEmpty { return true }
        guard path.hasPrefix("/") || path.hasPrefix("~/") else { return false }
        return !path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
