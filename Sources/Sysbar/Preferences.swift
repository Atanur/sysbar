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
        static let menuBarOrder = "menuBarOrder"
        static let visibleCards = "visibleCards"
        static let cardOrder = "cardOrder"
        static let cardLayout = "cardLayout"
        static let appColumns = "appColumns"
        static let showsApps = "showsApps"
        static let appRows = "appRows"
        static let coloredMenuBar = "coloredMenuBar"
        static let menuBarStyle = "menuBarStyle"
        static let batteryMenuBarThreshold = "batteryMenuBarThreshold"
        static let samplingInterval = "samplingInterval"
        static let temperatureUnit = "temperatureUnit"
        static let setupCompleted = "setupCompleted"
        static let remoteDevices = "remoteDevices"
        static let showsFanButton = "showsFanButton"
        static let showsKeepAwakeButton = "showsKeepAwakeButton"
        static let thisMacName = "thisMacName"
        static let searchesLocalNetwork = "searchesLocalNetwork"
        static let hiddenSuggestions = "hiddenSuggestions"
    }

    private let defaults: UserDefaults

    /// Every metric in the menu bar's order; the pinned ones are shown. At least one stays pinned.
    @Published private(set) var menuBarArrangement: Arrangement<MenuBarMetric>
    /// Every metric in the popover's order; the visible ones become cards. May have none visible.
    @Published private(set) var cardArrangement: Arrangement<MenuBarMetric>
    /// Columns of the apps table. Never empty.
    @Published private(set) var appColumns: [AppSortKey]
    /// Machines that can be monitored over SSH. Always valid: see `init`.
    @Published private(set) var devices: [RemoteDevice]

    @Published var cardLayout: CardLayoutMode {
        didSet { defaults.set(cardLayout.rawValue, forKey: Key.cardLayout) }
    }

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

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) }
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

    /// The temperature and fan button in the popover's top bar.
    @Published var showsFanButton: Bool {
        didSet { defaults.set(showsFanButton, forKey: Key.showsFanButton) }
    }

    /// The keep-awake-with-the-lid-closed button in the popover's top bar.
    @Published var showsKeepAwakeButton: Bool {
        didSet { defaults.set(showsKeepAwakeButton, forKey: Key.showsKeepAwakeButton) }
    }

    /// The name the user gave this Mac; empty shows "This Mac". See `thisMacTitle`.
    @Published var thisMacName: String {
        didSet {
            let normalized = LocalDeviceName.normalized(thisMacName)
            if normalized != thisMacName { thisMacName = normalized }
            defaults.set(normalized, forKey: Key.thisMacName)
        }
    }

    /// True once the user has asked to look for devices on this network, so Settings › Devices
    /// listens for them each time it opens. Off at first, because listening needs a macOS permission.
    @Published var searchesLocalNetwork: Bool {
        didSet { defaults.set(searchesLocalNetwork, forKey: Key.searchesLocalNetwork) }
    }

    /// Found devices the user does not want suggested, by `DeviceDiscovery.Found.id`.
    @Published var hiddenSuggestions: [String] {
        didSet { defaults.set(hiddenSuggestions, forKey: Key.hiddenSuggestions) }
    }

    /// This Mac's tab and row title: its given name, or "This Mac".
    var thisMacTitle: String {
        LocalDeviceName.display(thisMacName, fallback: L("This Mac"))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarArrangement = Arrangement(
            storedOrder: defaults.stringArray(forKey: Key.menuBarOrder),
            storedSelection: defaults.stringArray(forKey: Key.menuBarMetrics),
            defaultSelection: MenuBarMetric.defaults, emptyMeansDefault: true
        )
        cardArrangement = Arrangement(
            storedOrder: defaults.stringArray(forKey: Key.cardOrder),
            storedSelection: defaults.stringArray(forKey: Key.visibleCards),
            defaultSelection: MenuBarMetric.allCases, emptyMeansDefault: false
        )
        cardLayout = defaults.string(forKey: Key.cardLayout).flatMap(CardLayoutMode.init(rawValue:)) ?? .automatic
        let storedColumns: [AppSortKey]? = OrderedSelection.ordered(fromStored: defaults.stringArray(forKey: Key.appColumns))
        appColumns = (storedColumns?.isEmpty == false ? storedColumns : nil) ?? AppSortKey.allCases
        showsApps = defaults.object(forKey: Key.showsApps) as? Bool ?? true
        appRows = defaults.object(forKey: Key.appRows) as? Int ?? Self.defaultAppRows
        coloredMenuBar = defaults.object(forKey: Key.coloredMenuBar) as? Bool ?? true
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .barsAndValues
        batteryMenuBarThreshold = BatteryMenuBar.normalized(defaults.object(forKey: Key.batteryMenuBarThreshold) as? Int)
        samplingInterval = SamplingInterval.normalized(defaults.double(forKey: Key.samplingInterval))
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init(rawValue:))
            ?? .regionDefault
        setupCompleted = defaults.bool(forKey: Key.setupCompleted)
        showsFanButton = defaults.object(forKey: Key.showsFanButton) as? Bool ?? true
        showsKeepAwakeButton = defaults.object(forKey: Key.showsKeepAwakeButton) as? Bool ?? true
        thisMacName = LocalDeviceName.normalized(defaults.string(forKey: Key.thisMacName) ?? "")
        searchesLocalNetwork = defaults.bool(forKey: Key.searchesLocalNetwork)
        hiddenSuggestions = defaults.stringArray(forKey: Key.hiddenSuggestions) ?? []
        // Anything that fails validation is dropped, so edited or corrupt stored data can never
        // put an option-like value into an ssh command line.
        devices = Self.decodeDevices(defaults.data(forKey: Key.remoteDevices)).filter { $0.problems.isEmpty }
    }

    // MARK: Menu bar and cards

    /// Metrics pinned to the menu bar, in their order. Never empty.
    var menuBarMetrics: [MenuBarMetric] { menuBarArrangement.selected }
    /// Cards shown in the popover, in their order. May be empty.
    var visibleCards: [MenuBarMetric] { cardArrangement.selected }

    func isPinned(_ metric: MenuBarMetric) -> Bool {
        menuBarArrangement.contains(metric)
    }

    /// The last pinned metric cannot be removed.
    func isPinLocked(_ metric: MenuBarMetric) -> Bool {
        isPinned(metric) && menuBarMetrics.count == 1
    }

    func togglePin(_ metric: MenuBarMetric) {
        setMenuBar(menuBarArrangement.toggling(metric, minimum: 1))
    }

    func movePin(_ metric: MenuBarMetric, to target: MenuBarMetric) {
        setMenuBar(menuBarArrangement.moving(metric, to: target))
    }

    func movePin(_ metric: MenuBarMetric, by offset: Int) {
        setMenuBar(menuBarArrangement.moving(metric, by: offset))
    }

    func isCardVisible(_ metric: MenuBarMetric) -> Bool {
        cardArrangement.contains(metric)
    }

    func toggleCard(_ metric: MenuBarMetric) {
        setCards(cardArrangement.toggling(metric, minimum: 0))
    }

    func moveCard(_ metric: MenuBarMetric, to target: MenuBarMetric) {
        setCards(cardArrangement.moving(metric, to: target))
    }

    func moveCard(_ metric: MenuBarMetric, by offset: Int) {
        setCards(cardArrangement.moving(metric, by: offset))
    }

    private func setMenuBar(_ arrangement: Arrangement<MenuBarMetric>) {
        menuBarArrangement = arrangement
        defaults.set(arrangement.storedSelection, forKey: Key.menuBarMetrics)
        defaults.set(arrangement.storedOrder, forKey: Key.menuBarOrder)
    }

    private func setCards(_ arrangement: Arrangement<MenuBarMetric>) {
        cardArrangement = arrangement
        defaults.set(arrangement.storedSelection, forKey: Key.visibleCards)
        defaults.set(arrangement.storedOrder, forKey: Key.cardOrder)
    }

    // MARK: Reset

    /// Puts every setting on this object back to its default. Remote devices, this Mac's name and
    /// the device suggestions stay unless `keepingDevices` is false; the first-run welcome is not shown again.
    func resetToDefaults(keepingDevices: Bool) {
        setMenuBar(Arrangement(order: MenuBarMetric.allCases, selected: MenuBarMetric.defaults))
        setCards(Arrangement(order: MenuBarMetric.allCases, selected: MenuBarMetric.allCases))
        cardLayout = .automatic
        appColumns = AppSortKey.allCases
        defaults.set(OrderedSelection.storedValue(of: appColumns), forKey: Key.appColumns)
        showsApps = true
        appRows = Self.defaultAppRows
        coloredMenuBar = true
        menuBarStyle = .barsAndValues
        batteryMenuBarThreshold = BatteryMenuBar.defaultThreshold
        samplingInterval = SamplingInterval.defaultSeconds
        temperatureUnit = .regionDefault
        showsFanButton = true
        showsKeepAwakeButton = true
        if !keepingDevices {
            thisMacName = ""
            searchesLocalNetwork = false
            hiddenSuggestions = []
            devices = []
            persistDevices()
        }
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
