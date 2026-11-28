import Foundation

/// A page of the settings window. Each remote device has a page of its own, so the sidebar's
/// devices section is built from the device list.
public enum SettingsPage: Hashable, Sendable {
    case thisMac
    case device(UUID)
    /// Devices found on this network and in Tailscale, opened from the devices section's add button.
    case findDevices
    case general, menuBarReadouts, menuBarAppearance, notch, panel
    case fans, keepAwake, shelf, clipboard
    case about

    /// Where the settings window opens when no page is asked for: the first page of the sidebar.
    public static let start = SettingsPage.general

    /// Every page, in sidebar order, with finding devices last.
    public static func all(deviceIDs: [UUID]) -> [SettingsPage] {
        SettingsSection.allCases.flatMap { $0.pages(deviceIDs: deviceIDs) } + [.findDevices]
    }

    /// Where Sysbar lives when the page's settings apply, for the pages of the two places it can live.
    public var placement: SysbarPlacement? {
        switch self {
        case .menuBarAppearance: .menuBar
        case .notch: .notch
        default: nil
        }
    }

    /// The page to show: a device's page whose device has been removed goes back to this Mac.
    public func resolved(deviceIDs: [UUID]) -> SettingsPage {
        if case .device(let id) = self, !deviceIDs.contains(id) { return .thisMac }
        return self
    }
}

/// A group of pages in the settings sidebar, in its order: how Sysbar shows itself first, then its
/// features, the devices it watches, and About on its own at the end.
public enum SettingsSection: CaseIterable, Sendable {
    case display, features, devices, about

    public func pages(deviceIDs: [UUID]) -> [SettingsPage] {
        switch self {
        case .display: [.general, .menuBarReadouts, .menuBarAppearance, .notch, .panel]
        case .features: [.fans, .keepAwake, .shelf, .clipboard]
        case .devices: [.thisMac] + deviceIDs.map(SettingsPage.device)
        case .about: [.about]
        }
    }

    /// Whether the section has a titled header that folds it away; the first and last stand on their own.
    public var hasHeader: Bool { self == .features || self == .devices }
}
