import Foundation
import SysbarCore

/// Everything the user can configure, persisted in `UserDefaults`. Views and the status item both
/// observe this one object, so a change in the settings window shows up immediately.
@MainActor
final class Preferences: ObservableObject {
    static let appRowRange = 3...10
    private static let defaultAppRows = 6

    private enum Key {
        static let menuBarMetrics = "menuBarMetrics"
        static let visibleCards = "visibleCards"
        static let appColumns = "appColumns"
        static let showsApps = "showsApps"
        static let appRows = "appRows"
        static let coloredMenuBar = "coloredMenuBar"
        static let batteryMenuBarThreshold = "batteryMenuBarThreshold"
        static let samplingInterval = "samplingInterval"
        static let temperatureUnit = "temperatureUnit"
        static let setupCompleted = "setupCompleted"
        static let remoteDevices = "remoteDevices"
    }

    private let defaults: UserDefaults

    /// Metrics pinned to the menu bar. Never empty.
    @Published private(set) var menuBarMetrics: [MenuBarMetric]
    /// Cards shown in the popover. May be empty.
    @Published private(set) var visibleCards: [MenuBarMetric]
    /// Columns of the apps table. Never empty.
    @Published private(set) var appColumns: [AppSortKey]
    /// Machines that can be monitored over SSH. Always valid: see `init`.
    @Published private(set) var devices: [RemoteDevice]

    @Published var showsApps: Bool {
        didSet { defaults.set(showsApps, forKey: Key.showsApps) }
    }

    @Published var appRows: Int {
        didSet {
            let clamped = min(max(appRows, Self.appRowRange.lowerBound), Self.appRowRange.upperBound)
            if clamped != appRows { appRows = clamped }
            defaults.set(clamped, forKey: Key.appRows)
        }
    }

    @Published var coloredMenuBar: Bool {
        didSet { defaults.set(coloredMenuBar, forKey: Key.coloredMenuBar) }
    }

    /// Charge, in percent, at or below which the battery joins the menu bar while unplugged; zero is off.
    @Published var batteryMenuBarThreshold: Int {
        didSet { defaults.set(batteryMenuBarThreshold, forKey: Key.batteryMenuBarThreshold) }
    }

    @Published var samplingInterval: TimeInterval {
        didSet { defaults.set(samplingInterval, forKey: Key.samplingInterval) }
    }

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    /// True once the user has seen the first-run welcome.
    @Published var setupCompleted: Bool {
        didSet { defaults.set(setupCompleted, forKey: Key.setupCompleted) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMetrics = MenuBarMetric.metrics(fromStored: defaults.stringArray(forKey: Key.menuBarMetrics))
        visibleCards = MenuBarMetric.ordered(fromStored: defaults.stringArray(forKey: Key.visibleCards))
            ?? MenuBarMetric.allCases
        let storedColumns: [AppSortKey]? = OrderedSelection.ordered(fromStored: defaults.stringArray(forKey: Key.appColumns))
        appColumns = (storedColumns?.isEmpty == false ? storedColumns : nil) ?? AppSortKey.allCases
        showsApps = defaults.object(forKey: Key.showsApps) as? Bool ?? true
        appRows = defaults.object(forKey: Key.appRows) as? Int ?? Self.defaultAppRows
        coloredMenuBar = defaults.object(forKey: Key.coloredMenuBar) as? Bool ?? true
        batteryMenuBarThreshold = BatteryMenuBar.normalized(defaults.object(forKey: Key.batteryMenuBarThreshold) as? Int)
        samplingInterval = SamplingInterval.normalized(defaults.double(forKey: Key.samplingInterval))
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init(rawValue:))
            ?? .regionDefault
        setupCompleted = defaults.bool(forKey: Key.setupCompleted)
        // Anything that fails validation is dropped, so edited or corrupt stored data can never
        // put an option-like value into an ssh command line.
        devices = Self.decodeDevices(defaults.data(forKey: Key.remoteDevices)).filter { $0.problems.isEmpty }
    }

    // MARK: Menu bar and cards

    func isPinned(_ metric: MenuBarMetric) -> Bool {
        menuBarMetrics.contains(metric)
    }

    /// The last pinned metric cannot be removed.
    func isPinLocked(_ metric: MenuBarMetric) -> Bool {
        isPinned(metric) && menuBarMetrics.count == 1
    }

    func togglePin(_ metric: MenuBarMetric) {
        menuBarMetrics = MenuBarMetric.toggling(metric, in: menuBarMetrics)
        defaults.set(MenuBarMetric.storedValue(of: menuBarMetrics), forKey: Key.menuBarMetrics)
    }

    func isCardVisible(_ metric: MenuBarMetric) -> Bool {
        visibleCards.contains(metric)
    }

    func toggleCard(_ metric: MenuBarMetric) {
        visibleCards = MenuBarMetric.toggling(metric, in: visibleCards, minimum: 0)
        defaults.set(MenuBarMetric.storedValue(of: visibleCards), forKey: Key.visibleCards)
    }

    // MARK: Apps table columns

    func isColumnVisible(_ column: AppSortKey) -> Bool {
        appColumns.contains(column)
    }

    func isColumnLocked(_ column: AppSortKey) -> Bool {
        isColumnVisible(column) && appColumns.count == 1
    }

    func toggleColumn(_ column: AppSortKey) {
        appColumns = OrderedSelection.toggling(column, in: appColumns, minimum: 1)
        defaults.set(OrderedSelection.storedValue(of: appColumns), forKey: Key.appColumns)
    }

    // MARK: Remote devices

    func device(id: UUID) -> RemoteDevice? {
        devices.first { $0.id == id }
    }

    /// Adds the device, or replaces the one with the same id. Invalid devices are ignored.
    func saveDevice(_ device: RemoteDevice) {
        guard device.problems.isEmpty else { return }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices = devices.enumerated().map { $0.offset == index ? device : $0.element }
        } else {
            devices = devices + [device]
        }
        persistDevices()
    }

    func deleteDevice(id: UUID) {
        devices = devices.filter { $0.id != id }
        persistDevices()
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Key.remoteDevices)
        }
    }

    private static func decodeDevices(_ data: Data?) -> [RemoteDevice] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([RemoteDevice].self, from: data)) ?? []
    }
}

extension MenuBarMetric {
    /// Full name used in the settings window.
    var displayName: String {
        switch self {
        case .cpu: L("Processor (CPU)")
        case .gpu: L("Graphics (GPU)")
        case .memory: L("Memory (RAM)")
        case .power: L("Power")
        case .disk: L("Disk")
        case .network: L("Network")
        }
    }
}

extension AppSortKey {
    /// Column heading in the apps table and name in the settings window.
    var columnTitle: String {
        switch self {
        case .cpu: L("CPU")
        case .memory: L("RAM")
        case .gpu: L("GPU")
        case .power: L("Power")
        }
    }
}
