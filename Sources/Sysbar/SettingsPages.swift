import SysbarCore
import SwiftUI

/// Welcome (first run only) and an overview of this Mac.
struct GeneralPage: View {
    @ObservedObject var preferences: Preferences
    @State private var info = SystemInfoProbe.read()
    @State private var battery = BatteryProbe.read()
    @State private var copied = false

    var body: some View {
        SettingsPageScaffold(page: .general, animating: AnyHashable(preferences.setupCompleted)) {
            if !preferences.setupCompleted { welcome }

            SettingsGroup(title: L("This Mac")) {
                infoRow("cpu", L("Chip"), info.chip)
                RowDivider()
                infoRow("laptopcomputer", L("Model"), info.modelName ?? info.modelIdentifier)
                    .help(info.modelIdentifier)
                RowDivider()
                infoRow("apple.logo", L("System"), info.osVersion)
            }

            SettingsGroup(title: L("Hardware")) {
                infoRow("memorychip", L("Memory"), Format.gigabytes(info.memoryBytes))
                RowDivider()
                infoRow("square.grid.3x3", L("Cores"), coresText)
                if let total = info.diskTotalBytes, let free = info.diskFreeBytes {
                    RowDivider()
                    infoRow("internaldrive", L("Disk"), L("%1$@ free / %2$@", Format.gigabytes(free), Format.gigabytes(total)))
                }
                RowDivider()
                infoRow("clock", L("Uptime"), Format.uptime(info.uptime))
            }

            if let battery {
                SettingsGroup(title: L("Battery")) {
                    infoRow("battery.75", L("Charge"), PowerSummary.headline(battery: battery) ?? Format.percent(battery.fraction))
                    if let health = battery.health {
                        RowDivider()
                        infoRow("heart", L("Health"), Format.percent(health))
                    }
                    if let cycles = battery.cycleCount {
                        RowDivider()
                        infoRow("arrow.triangle.2.circlepath", L("Cycle count"), "\(cycles)")
                    }
                }
            }

            SettingsGroup {
                SettingsRow(symbol: "doc.on.doc", title: L("Copy as text"), subtitle: L("Everything on this page")) {
                    Button(copied ? L("Copied") : L("Copy"), action: copySummary)
                }
            }
        }
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var summary: String {
        var lines = [
            "\(L("Chip")): \(info.chip)",
            "\(L("Model")): \(info.modelName ?? info.modelIdentifier) (\(info.modelIdentifier))",
            "\(L("System")): \(info.osVersion)",
            "\(L("Memory")): \(Format.gigabytes(info.memoryBytes))",
            "\(L("Cores")): \(coresText)",
        ]
        if let total = info.diskTotalBytes, let free = info.diskFreeBytes {
            lines.append("\(L("Disk")): \(L("%1$@ free / %2$@", Format.gigabytes(free), Format.gigabytes(total)))")
        }
        lines.append("\(L("Uptime")): \(Format.uptime(info.uptime))")
        if let battery {
            lines.append("\(L("Battery")): \(PowerSummary.headline(battery: battery) ?? Format.percent(battery.fraction))")
            if let health = battery.health { lines.append("\(L("Health")): \(Format.percent(health))") }
            if let cycles = battery.cycleCount { lines.append("\(L("Cycle count")): \(cycles)") }
        }
        return lines.joined(separator: "\n")
    }

    /// "8 · 6 performance + 2 efficiency" on Apple silicon, the plain count elsewhere.
    private var coresText: String {
        let total = max(info.performanceCores + info.efficiencyCores, info.logicalCores)
        guard info.performanceCores > 0 else { return "\(total)" }
        return L("%1$@ · %2$@ performance + %3$@ efficiency", "\(total)", "\(info.performanceCores)", "\(info.efficiencyCores)")
    }

    private func infoRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var welcome: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "hand.wave.fill", size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Welcome to Sysbar")).font(.headline)
                Text(L("Sysbar runs in the menu bar and uses very few resources. Click the bar to open the detailed window. Choose what appears where on the pages at the left."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Get started")) { preferences.setupCompleted = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .settingsCard()
    }
}

/// Which metrics appear in the menu bar, and how, with a preview.
struct MenuBarPage: View {
    @ObservedObject var preferences: Preferences

    /// Only Macs with a battery offer the battery readout.
    private static let hasBattery = BatteryProbe.read() != nil

    /// Fixed sample values, so the preview shows every metric the way it will look. The battery
    /// sample sits under the chosen threshold, so the preview shows it whenever it is turned on.
    private static func sample(batteryThreshold: Int) -> Snapshot {
        let charge = batteryThreshold >= 50 ? 0.42 : 0.15
        return Snapshot(
            timestamp: Date(), cpuUsage: 0.23,
            memory: MemoryReading(usedBytes: 10_900_000_000, totalBytes: 17_179_869_184, pressure: .normal),
            power: nil, systemPower: 7.2, gpuUsage: 0.62,
            disk: IOThroughput(inbound: 1_200_000, outbound: 300_000),
            network: IOThroughput(inbound: 48_000, outbound: 9_000),
            battery: BatteryInfo(
                fraction: charge, isPluggedIn: false, isCharging: false, isFull: false, minutesRemaining: nil,
                cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
            )
        )
    }

    var body: some View {
        SettingsPageScaffold(page: .menuBar) {
            SettingsGroup(title: L("Preview")) { preview }

            SettingsGroup(
                title: L("Shown readouts"),
                footer: L("At least one readout must stay selected. Drag a row to change the order.")
            ) {
                ArrangedMetricRows(
                    order: preferences.menuBarArrangement.order,
                    move: preferences.movePin(_:to:), step: preferences.movePin(_:by:)
                ) { metric in
                    RowToggle(isOn: Binding(
                        get: { preferences.isPinned(metric) },
                        set: { _ in preferences.togglePin(metric) }
                    ))
                    .disabled(preferences.isPinLocked(metric))
                }
            }

            if Self.hasBattery {
                SettingsGroup(
                    title: L("Battery"),
                    footer: L("Shown only while running on battery. It turns from green to red as the charge runs low.")
                ) {
                    SettingsRow(symbol: "battery.50", title: L("Battery charge")) {
                        Picker("", selection: $preferences.batteryMenuBarThreshold) {
                            ForEach(BatteryMenuBar.thresholds, id: \.self) { Text(Self.thresholdTitle($0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
            }

            SettingsGroup(title: L("Appearance")) {
                SettingsRow(symbol: "rectangle.split.3x1", title: L("Style")) {
                    Picker("", selection: $preferences.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                SettingsRow(
                    symbol: "paintpalette.fill", title: L("Colored bars"),
                    subtitle: L("Bars turn from green to red as load rises")
                ) {
                    RowToggle(isOn: $preferences.coloredMenuBar)
                }
            }
        }
    }

    private static func thresholdTitle(_ threshold: Int) -> String {
        switch threshold {
        case BatteryMenuBar.off: L("Off")
        case 100: L("Always on battery")
        default: L("At %@ or less", Format.percent(Double(threshold) / 100))
        }
    }

    private var preview: some View {
        let threshold = Self.hasBattery ? preferences.batteryMenuBarThreshold : BatteryMenuBar.off
        let readouts = MenuBarReadouts.make(
            from: Self.sample(batteryThreshold: threshold), metrics: preferences.menuBarMetrics, batteryThreshold: threshold
        )
        let image = MenuBarImage.make(readouts, colored: preferences.coloredMenuBar, style: preferences.menuBarStyle)
        let keepsColors = MenuBarImage.keepsColors(readouts, colored: preferences.coloredMenuBar)
        let previewKey = MenuBarImage.signature(
            for: readouts, colored: preferences.coloredMenuBar, style: preferences.menuBarStyle
        )
        return HStack {
            Spacer()
            HStack(spacing: 14) {
                // A new look fades in over the old one.
                ZStack {
                    Image(nsImage: image)
                        .renderingMode(keepsColors ? .original : .template)
                        .foregroundStyle(.primary)
                        .id(previewKey)
                        .transition(.opacity)
                }
                .motion(.easeInOut(duration: 0.2), value: previewKey)
                Image(systemName: "wifi").foregroundStyle(.secondary)
                Text("12:01").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 18)
        .accessibilityLabel(L("Menu bar preview"))
    }
}

/// Which cards and which table the popover shows.
struct PopoverPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .popover, animating: AnyHashable(preferences.showsApps)) {
            SettingsGroup(title: L("Layout")) {
                SettingsRow(symbol: "square.grid.2x2", title: L("Card layout"), subtitle: layoutDetail) {
                    Picker("", selection: $preferences.cardLayout) {
                        ForEach(CardLayoutMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(
                title: L("Top bar buttons"),
                footer: L("Hiding a button also ends what it started: manual fan speed, or keeping the Mac awake.")
            ) {
                // The temperature button shows on any Mac that can read its sensors, fans or not.
                SettingsRow(symbol: "fan", title: L("Temperature and fans")) {
                    RowToggle(isOn: $preferences.showsFanButton)
                }
                RowDivider()
                SettingsRow(
                    symbol: KeepAwakeController.hasLid ? "laptopcomputer" : "cup.and.saucer",
                    title: KeepAwakeController.title
                ) {
                    RowToggle(isOn: $preferences.showsKeepAwakeButton)
                }
            }

            SettingsGroup(
                title: L("Cards"),
                footer: L("Drag a row to change the order. Clicking a card opens Activity Monitor, or Battery settings for power.")
            ) {
                ArrangedMetricRows(
                    order: preferences.cardArrangement.order,
                    move: preferences.moveCard(_:to:), step: preferences.moveCard(_:by:)
                ) { metric in
                    RowToggle(isOn: Binding(
                        get: { preferences.isCardVisible(metric) },
                        set: { _ in preferences.toggleCard(metric) }
                    ))
                }
            }

            SettingsGroup(title: L("Top apps")) {
                SettingsRow(symbol: "list.bullet", title: L("Show table")) {
                    RowToggle(isOn: $preferences.showsApps)
                }
                RowDivider()
                SettingsRow(symbol: "number", title: L("Row count")) {
                    Stepper(value: $preferences.appRows, in: Preferences.appRowRange) {
                        Text("\(preferences.appRows)").monospacedDigit().frame(minWidth: 20, alignment: .trailing)
                    }
                    .disabled(!preferences.showsApps)
                }
            }

            SettingsGroup(title: L("Table columns"), footer: L("At least one column must stay visible.")) {
                ForEach(Array(AppSortKey.allCases.enumerated()), id: \.element) { index, column in
                    if index > 0 { RowDivider() }
                    SettingsRow(symbol: column.symbol, title: column.columnTitle) {
                        RowToggle(isOn: Binding(
                            get: { preferences.isColumnVisible(column) },
                            set: { _ in preferences.toggleColumn(column) }
                        ))
                        .disabled(!preferences.showsApps || preferences.isColumnLocked(column))
                    }
                }
            }
        }
    }

    private var layoutDetail: String {
        switch preferences.cardLayout {
        case .automatic: L("Two columns for an even number of cards, one for an odd number")
        case .oneColumn: L("Cards stack in a single list")
        case .twoColumns: L("Always side by side")
        }
    }
}

extension MenuBarStyle {
    var title: String {
        switch self {
        case .barsAndValues: L("Bars and values")
        case .barsOnly: L("Bars only")
        case .valuesOnly: L("Values only")
        }
    }
}

extension CardLayoutMode {
    var title: String {
        switch self {
        case .automatic: L("Automatic")
        case .oneColumn: L("One column")
        case .twoColumns: L("Two columns")
        }
    }
}

/// Sampling and start-up behaviour.
struct PreferencesPage: View {
    @ObservedObject var preferences: Preferences
    let updater: UpdateChecker
    @ObservedObject var helper: HelperConnection
    @State private var confirmsReset = false

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var language = AppLanguage.current
    private let launchLanguage = AppLanguage.current

    var body: some View {
        SettingsPageScaffold(page: .preferences) {
            SettingsGroup(title: L("Language")) {
                SettingsRow(symbol: "globe", title: L("Language")) {
                    Picker("", selection: Binding(get: { language }, set: { language = $0; AppLanguage.select($0) })) {
                        ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if language != launchLanguage {
                    RowDivider()
                    SettingsRow(symbol: "arrow.clockwise", title: L("Restart Sysbar to use the new language")) {
                        Button(L("Restart")) { AppLanguage.relaunch() }
                    }
                }
            }

            SettingsGroup(
                title: L("Sampling"),
                footer: L("Faster refreshes use more CPU. Each graph holds 150 samples, so its time span follows the refresh rate. The apps table refreshes at most once a second, and each remote device has its own rate.")
            ) {
                SettingsRow(
                    symbol: "laptopcomputer", title: L("This Mac"),
                    subtitle: L("Refresh rate · graphs show %@", SamplingInterval.windowText(for: preferences.samplingInterval))
                ) {
                    IntervalSlider(
                        value: $preferences.samplingInterval,
                        range: SamplingInterval.localRange,
                        step: SamplingInterval.localStep,
                        normalize: SamplingInterval.normalized,
                        debounce: .milliseconds(500)
                    )
                }
            }

            SettingsGroup(title: L("Units")) {
                SettingsRow(symbol: "thermometer.medium", title: L("Temperature")) {
                    Picker("", selection: $preferences.temperatureUnit) {
                        Text(L("Celsius")).tag(TemperatureUnit.celsius)
                        Text(L("Fahrenheit")).tag(TemperatureUnit.fahrenheit)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(title: L("Startup"), footer: launchError) {
                SettingsRow(symbol: "power", title: L("Launch at login")) {
                    RowToggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                }
            }

            if helper.isNeeded {
                SettingsGroup(title: L("Helper"), footer: helper.setupError ?? helperFooter) {
                    SettingsRow(symbol: "lock.shield", title: L("Sysbar's helper"), subtitle: helperStatus) {
                        helperAction
                    }
                }
            }

            SettingsGroup(title: L("Reset")) {
                SettingsRow(
                    symbol: "arrow.counterclockwise", title: L("Reset all settings"),
                    subtitle: L("Language and launch at login are kept")
                ) {
                    Button(L("Reset…")) { confirmsReset = true }
                }
            }
            .confirmationDialog(L("Reset all settings?"), isPresented: $confirmsReset) {
                Button(L("Reset, keep remote devices")) { reset(keepingDevices: true) }
                Button(L("Reset and remove remote devices"), role: .destructive) { reset(keepingDevices: false) }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Menu bar, window, sampling and update settings go back to their defaults."))
            }
        }
    }

    private var helperStatus: String {
        switch helper.state {
        case .ready: L("Set up; used from the popover")
        case .needsApproval: L("Waiting for approval in System Settings")
        case .notInstalled: L("Not set up")
        case .unavailable: L("Needs a signed copy of Sysbar")
        }
    }

    private var helperFooter: String {
        L("The helper runs only while Sysbar uses it and can only set fan speeds and keep the Mac awake with the lid closed. Both end when Sysbar quits or crashes.")
    }

    @ViewBuilder
    private var helperAction: some View {
        switch helper.state {
        case .ready:
            HStack {
                if helper.isUnresponsive { Button(L("Set up again")) { Task { await helper.reinstall() } } }
                Button(L("Remove")) { Task { await helper.uninstall() } }
            }
        case .needsApproval: Button(L("Open System Settings")) { helper.openApprovalSettings() }
        case .notInstalled: Button(L("Set up…")) { helper.install() }
        case .unavailable: EmptyView()
        }
    }

    private func reset(keepingDevices: Bool) {
        preferences.resetToDefaults(keepingDevices: keepingDevices)
        updater.resetToDefaults()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = L("Could not change the setting: %@", error.localizedDescription)
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
