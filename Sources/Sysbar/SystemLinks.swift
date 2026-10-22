import AppKit
import SysbarCore

/// Opens the part of macOS that shows more about a metric when its card is clicked.
///
/// Activity Monitor has no way to be told which tab to show, other than its own `SelectedTab`
/// preference, which it reads at launch. So the tab is chosen only when Activity Monitor is not
/// already running; if it is, it is just brought to the front rather than switching tabs with
/// synthetic key presses (which would need the Accessibility permission).
enum SystemLinks {
    enum Target: Equatable {
        case activityMonitor(tab: Int)
        case batterySettings
    }

    private static let activityMonitorURL = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
    private static let activityMonitorID = "com.apple.ActivityMonitor"
    private static let batterySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")

    /// Activity Monitor tabs in order: CPU, Memory, Energy, Disk, Network. It has no GPU tab, so GPU
    /// opens the CPU tab, whose Window menu leads to GPU History.
    static func target(for metric: MenuBarMetric, hasBattery: Bool) -> Target {
        switch metric {
        case .cpu, .gpu: .activityMonitor(tab: 0)
        case .memory: .activityMonitor(tab: 1)
        case .power: hasBattery ? .batterySettings : .activityMonitor(tab: 2)
        case .disk: .activityMonitor(tab: 3)
        case .network: .activityMonitor(tab: 4)
        }
    }

    static func open(_ target: Target) {
        switch target {
        case .batterySettings:
            if let url = batterySettingsURL { NSWorkspace.shared.open(url) }
        case .activityMonitor(let tab):
            let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: activityMonitorID).isEmpty
            if !isRunning { preselectTab(tab) }
            NSWorkspace.shared.openApplication(at: activityMonitorURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func preselectTab(_ tab: Int) {
        CFPreferencesSetAppValue("SelectedTab" as CFString, tab as CFNumber, activityMonitorID as CFString)
        CFPreferencesAppSynchronize(activityMonitorID as CFString)
    }
}
