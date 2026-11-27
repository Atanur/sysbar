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
        static let sysbarPlacement = "sysbarPlacement"
        static let notchDisplays = "notchDisplays"
        static let notchBackground = "notchBackground"
        static let notchIconStyle = "notchIconStyle"
        static let notchIconSize = "notchIconSize"
        static let notchOpening = "notchOpening"
        static let notchVisibility = "notchVisibility"
        static let notchLeftCount = "notchLeftCount"
        static let notchLeftHidden = "notchLeftHidden"
        /// The icons the right ear used to leave out; only read, once, to migrate to `notchEars`.
        static let notchRightHidden = "notchRightHidden"
        static let notchEars = "notchEars"
        static let shelfEnabled = "shelfEnabled"
        static let shelfShake = "shelfShake"
        static let shelfSensitivity = "shelfSensitivity"
        static let shelfModifierEnabled = "shelfModifierEnabled"
        static let shelfModifier = "shelfModifier"
        static let shelfShortcuts = "shelfShortcuts"
        static let shelfNotchEnabled = "shelfNotchEnabled"
        static let shelfIgnoredApps = "shelfIgnoredApps"
        static let shelfHistory = "shelfHistory"
        static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
        static let clipboardHistoryLimit = "clipboardHistoryLimit"
        static let clipboardIgnoredApps = "clipboardIgnoredApps"
        static let clipboardLocation = "clipboardLocation"
        static let clipboardRetention = "clipboardRetention"
        static let clipboardKinds = "clipboardKinds"
        static let clipboardImageLimit = "clipboardImageLimit"
        static let clipboardKeepsDuplicates = "clipboardKeepsDuplicates"
        static let shelfLocation = "shelfLocation"
        static let shelfDefaultStash = "shelfDefaultStash"
        static let shelfDeleteMovesItems = "shelfDeleteMovesItems"
        static let keepAwakeSwitchDefault = "keepAwakeSwitchDefault"
        static let keepAwakeLastDuration = "keepAwakeLastDuration"
        static let keepAwakeMouseIdle = "keepAwakeMouseIdle"
        static let keepAwakeLowBattery = "keepAwakeLowBattery"
        static let heatWarning = "heatWarning"
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

    /// Where Sysbar shows itself: its menu bar item, or around the notch (a capsule at the top of a
    /// screen without one). Only one of them at a time.
    @Published var sysbarPlacement: SysbarPlacement {
        didSet { defaults.set(sysbarPlacement.rawValue, forKey: Key.sysbarPlacement) }
    }

    /// Which displays get an island while Sysbar is at the top of the screen.
    @Published var notchDisplays: NotchDisplayChoice {
        didSet { defaults.set(notchDisplays.rawValue, forKey: Key.notchDisplays) }
    }
    /// What fills the island, whether its icons keep their colours and how big they are, and what opens it.
    @Published var notchBackground: NotchBackground {
        didSet { defaults.set(notchBackground.rawValue, forKey: Key.notchBackground) }
    }
    @Published var notchIconStyle: NotchIconStyle {
        didSet { defaults.set(notchIconStyle.rawValue, forKey: Key.notchIconStyle) }
    }
    @Published var notchIconSize: NotchIconSize {
        didSet { defaults.set(notchIconSize.rawValue, forKey: Key.notchIconSize) }
    }
    @Published var notchOpening: NotchOpening {
        didSet { defaults.set(notchOpening.rawValue, forKey: Key.notchOpening) }
    }
    /// Whether the island is always there or only while the pointer is on it. In full screen it is the latter regardless.
    @Published var notchVisibility: NotchIslandVisibility {
        didSet { defaults.set(notchVisibility.rawValue, forKey: Key.notchVisibility) }
    }
    /// How many readouts the island's left ear shows at most, 0 for none, and which readouts (by
    /// `MenuBarSlot.id`) it leaves out. What each ear holds, in what order, and which items show only
    /// while the island is open.
    @Published var notchLeftCount: Int {
        didSet {
            notchLeftCount = Self.clampedEarCount(notchLeftCount)
            defaults.set(notchLeftCount, forKey: Key.notchLeftCount)
        }
    }
    @Published var notchLeftHidden: [String] {
        didSet { defaults.set(notchLeftHidden, forKey: Key.notchLeftHidden) }
    }
    @Published var notchEars: NotchEarLayout {
        didSet { if let data = try? JSONEncoder().encode(notchEars) { defaults.set(data, forKey: Key.notchEars) } }
    }

    static let earCountRange = 0...4
    static func clampedEarCount(_ count: Int) -> Int { min(max(count, earCountRange.lowerBound), earCountRange.upperBound) }

    /// Adds `id` to a list of hidden ids or takes it out.
    static func toggled(_ id: String, in hidden: [String]) -> [String] {
        hidden.contains(id) ? hidden.filter { $0 != id } : hidden + [id]
    }

    /// The stash: named collections of files and text, with a picker that opens while files are dragged,
    /// and its tab in the popover. Off until the user turns it on.
    @Published var shelfEnabled: Bool {
        didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) }
    }

    /// Shaking the pointer during a file drag opens the stash picker, and how hard that shake must be.
    @Published var shelfShake: Bool {
        didSet { defaults.set(shelfShake, forKey: Key.shelfShake) }
    }
    @Published var shelfSensitivity: DragShake.Sensitivity {
        didSet { defaults.set(shelfSensitivity.rawValue, forKey: Key.shelfSensitivity) }
    }

    /// Holding a key during a file drag opens the stash picker, and which key.
    @Published var shelfModifierEnabled: Bool {
        didSet { defaults.set(shelfModifierEnabled, forKey: Key.shelfModifierEnabled) }
    }
    @Published var shelfModifier: ShelfModifier {
        didSet { defaults.set(shelfModifier.rawValue, forKey: Key.shelfModifier) }
    }

    /// Global shortcuts by action: "new", "clipboard" and "history".
    @Published var shelfShortcuts: [String: KeyShortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shelfShortcuts), forKey: Key.shelfShortcuts) }
    }

    /// Dragging files onto the island at the top of the screen opens the stash picker in it.
    @Published var shelfNotchEnabled: Bool {
        didSet { defaults.set(shelfNotchEnabled, forKey: Key.shelfNotchEnabled) }
    }

    /// Bundle identifiers of apps whose drags never open the stash picker.
    @Published var shelfIgnoredApps: [String] {
        didSet { defaults.set(shelfIgnoredApps, forKey: Key.shelfIgnoredApps) }
    }

    /// Shelves put away before stashes were named, newest first. Read once, to carry their files over to
    /// the main stash; the saved value is left alone.
    var legacyShelfHistory: [ShelfRecord] {
        defaults.data(forKey: Key.shelfHistory).flatMap { try? JSONDecoder().decode([ShelfRecord].self, from: $0) } ?? []
    }

    /// The folder the stashes' own folder sits in; empty is the default, `StorageLocation.defaultParent`.
    /// Changed only by `ShelfController.relocate`, which moves the file first.
    @Published var shelfLocation: String {
        didSet { defaults.set(shelfLocation, forKey: Key.shelfLocation) }
    }
    /// The stash the Add Clipboard to Stash shortcut uses (a stash id); empty means the last one used.
    @Published var shelfDefaultStash: String {
        didSet { defaults.set(shelfDefaultStash, forKey: Key.shelfDefaultStash) }
    }
    /// Deleting a stash moves its items to Main (the default) or deletes them with it.
    @Published var shelfDeleteMovesItems: Bool {
        didSet { defaults.set(shelfDeleteMovesItems, forKey: Key.shelfDeleteMovesItems) }
    }

    /// Keeps what is copied, on this Mac only, for the history panel and the Clipboard tab. Off until
    /// the user turns it on; independent of the stash. Turning it off deletes the history.
    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipboardHistoryEnabled) }
    }
    /// How many copied items are kept; one of `ClipboardHistory.limits`.
    @Published var clipboardHistoryLimit: Int {
        didSet { defaults.set(clipboardHistoryLimit, forKey: Key.clipboardHistoryLimit) }
    }
    /// Bundle identifiers of apps whose copies are never kept.
    @Published var clipboardIgnoredApps: [String] {
        didSet { defaults.set(clipboardIgnoredApps, forKey: Key.clipboardIgnoredApps) }
    }
    /// The folder the history's own folder sits in; empty is the default. Changed only by
    /// `ClipboardController.relocate`, which moves the history first.
    @Published var clipboardLocation: String {
        didSet { defaults.set(clipboardLocation, forKey: Key.clipboardLocation) }
    }
    /// How long copies are kept, counted from the last copy.
    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }
    /// Which kinds of copies are recorded.
    @Published var clipboardKinds: Set<ClipboardKind> {
        didSet { defaults.set(ClipboardRecording.stored(clipboardKinds), forKey: Key.clipboardKinds) }
    }
    /// The largest image kept, in megabytes; one of `ClipboardHistory.imageLimits`.
    @Published var clipboardImageLimit: Int {
        didSet { defaults.set(clipboardImageLimit, forKey: Key.clipboardImageLimit) }
    }
    /// A repeated copy is kept as another item, instead of moving the first one to the top.
    @Published var clipboardKeepsDuplicates: Bool {
        didSet { defaults.set(clipboardKeepsDuplicates, forKey: Key.clipboardKeepsDuplicates) }
    }

    /// The Show Clipboard History shortcut. Kept with the other shortcuts, under the name the stash
    /// gave it, so a shortcut recorded before the clipboard had its own page still works.
    var clipboardShortcut: KeyShortcut? {
        get { shelfShortcuts["history"] }
        set { shelfShortcuts["history"] = newValue }
    }

    /// What the Keep awake switch starts, and the duration last picked from the menu (for `lastUsed`).
    @Published var keepAwakeSwitchDefault: KeepAwakeSwitchDefault {
        didSet { defaults.set(keepAwakeSwitchDefault.rawValue, forKey: Key.keepAwakeSwitchDefault) }
    }
    @Published var keepAwakeLastDuration: KeepAwakeDuration {
        didSet { defaults.set(keepAwakeLastDuration.rawValue, forKey: Key.keepAwakeLastDuration) }
    }
    /// Seconds without input before the cursor moves, and the charge at or below which keeping awake ends on battery.
    @Published var keepAwakeMouseIdle: Double {
        didSet { defaults.set(keepAwakeMouseIdle, forKey: Key.keepAwakeMouseIdle) }
    }
    @Published var keepAwakeLowBattery: Int {
        didSet { defaults.set(keepAwakeLowBattery, forKey: Key.keepAwakeLowBattery) }
    }
    /// How early the heat warning comes.
    @Published var heatWarning: HeatWarning {
        didSet { defaults.set(heatWarning.rawValue, forKey: Key.heatWarning) }
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
        sysbarPlacement = defaults.string(forKey: Key.sysbarPlacement).flatMap(SysbarPlacement.init(rawValue:)) ?? .menuBar
        notchDisplays = defaults.string(forKey: Key.notchDisplays).flatMap(NotchDisplayChoice.init(rawValue:)) ?? .builtIn
        notchBackground = defaults.string(forKey: Key.notchBackground).flatMap(NotchBackground.init(rawValue:)) ?? .automatic
        notchIconStyle = defaults.string(forKey: Key.notchIconStyle).flatMap(NotchIconStyle.init(rawValue:)) ?? .colored
        notchIconSize = defaults.string(forKey: Key.notchIconSize).flatMap(NotchIconSize.init(rawValue:)) ?? .medium
        notchOpening = defaults.string(forKey: Key.notchOpening).flatMap(NotchOpening.init(rawValue:)) ?? .hover
        notchVisibility = defaults.string(forKey: Key.notchVisibility).flatMap(NotchIslandVisibility.init(rawValue:)) ?? .always
        notchLeftCount = Self.clampedEarCount(defaults.object(forKey: Key.notchLeftCount) as? Int ?? NotchGeometry.leftEarReadouts)
        notchLeftHidden = defaults.stringArray(forKey: Key.notchLeftHidden) ?? []
        // Icons hidden under the old right-ear switches were hidden on the closed island only.
        notchEars = defaults.data(forKey: Key.notchEars).flatMap { try? JSONDecoder().decode(NotchEarLayout.self, from: $0) }
            ?? .migrated(hiddenFeatures: defaults.stringArray(forKey: Key.notchRightHidden) ?? [])
        shelfEnabled = defaults.bool(forKey: Key.shelfEnabled)
        shelfShake = defaults.object(forKey: Key.shelfShake) as? Bool ?? true
        shelfSensitivity = defaults.string(forKey: Key.shelfSensitivity).flatMap(DragShake.Sensitivity.init(rawValue:)) ?? .standard
        shelfModifierEnabled = defaults.object(forKey: Key.shelfModifierEnabled) as? Bool ?? true
        shelfModifier = defaults.string(forKey: Key.shelfModifier).flatMap(ShelfModifier.init(rawValue:)) ?? .shift
        shelfShortcuts = defaults.data(forKey: Key.shelfShortcuts)
            .flatMap { try? JSONDecoder().decode([String: KeyShortcut].self, from: $0) } ?? [:]
        shelfNotchEnabled = defaults.object(forKey: Key.shelfNotchEnabled) as? Bool ?? true
        shelfIgnoredApps = defaults.stringArray(forKey: Key.shelfIgnoredApps) ?? []
        clipboardHistoryEnabled = defaults.bool(forKey: Key.clipboardHistoryEnabled)
        clipboardHistoryLimit = ClipboardHistory.normalizedLimit(defaults.object(forKey: Key.clipboardHistoryLimit) as? Int)
        clipboardIgnoredApps = defaults.stringArray(forKey: Key.clipboardIgnoredApps) ?? ClipboardPrivacy.defaultIgnoredApps
        clipboardLocation = defaults.string(forKey: Key.clipboardLocation) ?? ""
        clipboardRetention = ClipboardRetention.normalized(defaults.string(forKey: Key.clipboardRetention))
        clipboardKinds = ClipboardRecording.normalized(stored: defaults.stringArray(forKey: Key.clipboardKinds))
        clipboardImageLimit = ClipboardHistory.normalizedImageLimit(defaults.object(forKey: Key.clipboardImageLimit) as? Int)
        clipboardKeepsDuplicates = defaults.bool(forKey: Key.clipboardKeepsDuplicates)
        shelfLocation = defaults.string(forKey: Key.shelfLocation) ?? ""
        shelfDefaultStash = defaults.string(forKey: Key.shelfDefaultStash) ?? ""
        shelfDeleteMovesItems = defaults.object(forKey: Key.shelfDeleteMovesItems) as? Bool ?? true
        keepAwakeSwitchDefault = KeepAwakeSwitchDefault.normalized(defaults.string(forKey: Key.keepAwakeSwitchDefault))
        keepAwakeLastDuration = KeepAwakeDuration.normalized(defaults.string(forKey: Key.keepAwakeLastDuration))
        keepAwakeMouseIdle = MouseWander.normalizedIdle(defaults.object(forKey: Key.keepAwakeMouseIdle) as? Double)
        keepAwakeLowBattery = KeepAwakePolicy.normalizedLowBattery(defaults.object(forKey: Key.keepAwakeLowBattery) as? Int)
        heatWarning = HeatWarning.normalized(defaults.string(forKey: Key.heatWarning))
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
        sysbarPlacement = .menuBar
        notchDisplays = .builtIn
        notchBackground = .automatic
        notchIconStyle = .colored
        notchIconSize = .medium
        notchOpening = .hover
        notchVisibility = .always
        notchLeftCount = NotchGeometry.leftEarReadouts
        notchLeftHidden = []
        notchEars = .standard
        shelfEnabled = false
        shelfShake = true
        shelfSensitivity = .standard
        shelfModifierEnabled = true
        shelfModifier = .shift
        shelfShortcuts = [:]
        shelfNotchEnabled = true
        shelfIgnoredApps = []
        shelfDefaultStash = ""
        shelfDeleteMovesItems = true
        // Whether the history is on, and where it and the stashes are kept, stay: turning it off deletes
        // it, and another folder would leave the data behind.
        clipboardHistoryLimit = ClipboardHistory.defaultLimit
        clipboardIgnoredApps = ClipboardPrivacy.defaultIgnoredApps
        clipboardRetention = .forever
        clipboardKinds = Set(ClipboardKind.allCases)
        clipboardImageLimit = ClipboardHistory.defaultImageLimit
        clipboardKeepsDuplicates = false
        keepAwakeSwitchDefault = .untilOff
        keepAwakeLastDuration = .untilOff
        keepAwakeMouseIdle = MouseWander.idleSecondsBeforeMoving
        keepAwakeLowBattery = KeepAwakePolicy.lowBatteryPercent
        heatWarning = .standard
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
        case .network: L("Network")
        }
    }

    /// A narrower heading for the table, where "Network" plus the sort mark does not fit.
    var headerTitle: String {
        self == .network ? L("Net") : columnTitle
    }
}
