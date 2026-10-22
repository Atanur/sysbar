import SysbarCore
import SwiftUI

/// Welcome (first run only) and an overview of this Mac.
struct GeneralPage: View {
    @ObservedObject var preferences: Preferences
    @State private var info = SystemInfoProbe.read()

    var body: some View {
        SettingsPageScaffold(page: .general) {
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
        }
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

            SettingsGroup(title: L("Shown readouts"), footer: L("At least one readout must stay selected.")) {
                ForEach(Array(MenuBarMetric.allCases.enumerated()), id: \.element) { index, metric in
                    if index > 0 { RowDivider() }
                    SettingsRow(symbol: metric.symbol, title: metric.displayName) {
                        RowToggle(isOn: Binding(
                            get: { preferences.isPinned(metric) },
                            set: { _ in preferences.togglePin(metric) }
                        ))
                        .disabled(preferences.isPinLocked(metric))
                    }
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
        let image = MenuBarImage.make(readouts, colored: preferences.coloredMenuBar)
        let keepsColors = MenuBarImage.keepsColors(readouts, colored: preferences.coloredMenuBar)
        return HStack {
            Spacer()
            HStack(spacing: 14) {
                Image(nsImage: image)
                    .renderingMode(keepsColors ? .original : .template)
                    .foregroundStyle(.primary)
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
        SettingsPageScaffold(page: .popover) {
            SettingsGroup(
                title: L("Cards"),
                footer: L("An odd number of cards shows in one column, an even number in two. Clicking a card opens Activity Monitor, or Battery settings for power.")
            ) {
                ForEach(Array(MenuBarMetric.allCases.enumerated()), id: \.element) { index, metric in
                    if index > 0 { RowDivider() }
                    SettingsRow(symbol: metric.symbol, title: metric.displayName) {
                        RowToggle(isOn: Binding(
                            get: { preferences.isCardVisible(metric) },
                            set: { _ in preferences.toggleCard(metric) }
                        ))
                    }
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
}

/// Sampling and start-up behaviour.
struct PreferencesPage: View {
    @ObservedObject var preferences: Preferences
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
        }
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

/// Version, data sources, and the limits of what can be measured.
struct AboutPage: View {
    let updater: UpdateChecker

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("development")
    }

    var body: some View {
        SettingsPageScaffold(page: .about) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Sysbar").font(.title.weight(.semibold))
                Text(L("Version %@", version)).foregroundStyle(.secondary)
                Text(L("A lightweight system monitor for the menu bar.")).padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .settingsCard()

            UpdateSettingsGroup(updater: updater)

            SettingsGroup(title: L("Data sources")) {
                infoRow("cpu", L("CPU, memory, disk and network"), L("macOS kernel counters"))
                RowDivider()
                infoRow("display", L("GPU usage"), L("Statistics from the graphics driver"))
                RowDivider()
                infoRow("bolt.fill", L("Power"), L("Total SMC power, energy counters and battery log"))
                RowDivider()
                infoRow("list.bullet", L("Per-app values"), L("Only processes from your own account"))
                RowDivider()
                infoRow("server.rack", L("Remote devices"), L("Using ssh, a key or ssh-agent on your system"))
            }

            SettingsGroup(title: L("Limits")) {
                infoRow("exclamationmark.triangle.fill", L("CPU and RAM power"),
                        L("On this macOS version it cannot be read without privileges, so it is not shown"))
                RowDivider()
                infoRow("exclamationmark.triangle.fill", L("Power per app"),
                        L("An estimate from the system, lower than the total"))
            }
        }
    }

    private func infoRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        SettingsRow(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}
