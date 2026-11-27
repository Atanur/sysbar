import Foundation

/// A page of the settings window. Each remote device has a page of its own, so the sidebar's
/// devices section is built from the device list.
public enum SettingsPage: Hashable, Sendable {
    case thisMac
    case device(UUID)
    /// Devices found on this network and in Tailscale, opened from the devices section's add button.
    case findDevices
    case menuBarReadouts, menuBarAppearance, notch
    case windowLayout, appsTable
    case fans, keepAwake, shelf, clipboard
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

/// A titled group of pages in the settings sidebar, in its order: the app's own pages first.
public enum SettingsSection: CaseIterable, Sendable {
    case app, devices, menuBar, window, tools

    public func pages(deviceIDs: [UUID]) -> [SettingsPage] {
        switch self {
        case .devices: [.thisMac] + deviceIDs.map(SettingsPage.device)
        case .menuBar: [.menuBarReadouts, .menuBarAppearance, .notch]
        case .window: [.windowLayout, .appsTable]
        case .tools: [.fans, .keepAwake, .shelf, .clipboard]
        case .app: [.general, .about]
        }
    }
}
