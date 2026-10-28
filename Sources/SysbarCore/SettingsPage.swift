import Foundation

/// A page of the settings window. Each remote device has a page of its own, so the sidebar's
/// devices section is built from the device list.
public enum SettingsPage: Hashable, Sendable {
    case thisMac
    case device(UUID)
    /// Devices found on this network and in Tailscale, opened from the devices section's add button.
    case findDevices
    case menuBarReadouts, menuBarAppearance
    case windowLayout, appsTable
    case fans, keepAwake
    case general, about

    /// Where the settings window opens when no page is asked for.
    public static let start = SettingsPage.thisMac

    /// Every page, in sidebar order, with finding devices last.
    public static func all(deviceIDs: [UUID]) -> [SettingsPage] {
        SettingsSection.allCases.flatMap { $0.pages(deviceIDs: deviceIDs) } + [.findDevices]
    }

    /// The page to show: a device's page whose device has been removed goes back to this Mac.
    public func resolved(deviceIDs: [UUID]) -> SettingsPage {
        if case .device(let id) = self, !deviceIDs.contains(id) { return .thisMac }
        return self
    }
}

/// A titled group of pages in the settings sidebar.
public enum SettingsSection: CaseIterable, Sendable {
    case devices, menuBar, window, tools, app

    public func pages(deviceIDs: [UUID]) -> [SettingsPage] {
        switch self {
        case .devices: [.thisMac] + deviceIDs.map(SettingsPage.device)
        case .menuBar: [.menuBarReadouts, .menuBarAppearance]
        case .window: [.windowLayout, .appsTable]
        case .tools: [.fans, .keepAwake]
        case .app: [.general, .about]
        }
    }
}
