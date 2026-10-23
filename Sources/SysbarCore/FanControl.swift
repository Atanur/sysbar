import Foundation
import Security

/// What the app and its privileged fan helper agree on. The helper accepts exactly these two
/// requests, and only from a copy of Sysbar signed by the same team.
@objc public protocol FanControlProtocol {
    /// Runs every fan at `fraction` of the way from its minimum (0) to its maximum (1) speed.
    /// Replies with nil on success, or a short reason it could not.
    func setManual(fraction: Double, reply: @escaping (String?) -> Void)
    /// Hands the fans back to macOS's own control.
    func setAutomatic(reply: @escaping (String?) -> Void)
}

public enum FanControlLimits {
    public static let helperLabel = "com.atanur.sysbar.fanhelper"
    public static let helperPlist = "\(helperLabel).plist"
    public static let appIdentifier = "com.atanur.sysbar"
    /// Fan indices probed; Macs have at most two today.
    public static let maximumFans = 8
    /// Manual mode lapses back to automatic unless the app renews it within this time, so fans
    /// never stay pinned if the app hangs while still connected.
    public static let leaseSeconds = 15.0
    /// How often the app renews manual mode; well inside the lease.
    public static let renewSeconds = 5.0
    /// Fan speed limits reported outside this range are treated as unreadable.
    public static let plausibleRPM = 0.0...20_000.0

    /// The speed a manual `fraction` asks of a fan: never below its own minimum or above its
    /// maximum. Nil for a fraction outside 0...1 or a speed range that makes no sense.
    public static func targetRPM(fraction: Double, minimum: Double, maximum: Double) -> Double? {
        guard
            fraction.isFinite, (0...1).contains(fraction),
            plausibleRPM.contains(minimum), plausibleRPM.contains(maximum), minimum <= maximum
        else { return nil }
        return minimum + (maximum - minimum) * fraction
    }

    /// The team that signed the running code; nil for an ad-hoc development build. The app and
    /// the helper each accept only a peer signed by the same team.
    public static func signingTeam() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard
            SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The code signing rule one side of the connection requires of the other: the given
    /// identifier, signed with an Apple-issued certificate of `team`.
    public static func requirement(identifier: String, team: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}
