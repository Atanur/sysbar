import SysbarCore
import SwiftUI

/// Which metrics appear in the menu bar, in what order, and when the battery joins them.
struct MenuBarReadoutsPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .menuBarReadouts) {
            SettingsGroup(title: L("Preview")) { MenuBarPreview(preferences: preferences) }

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

            if MenuBarPreview.hasBattery {
                SettingsGroup(
                    title: L("Battery"),
                    footer: L("Shown only while running on battery. It stays neutral, then turns amber and red as the charge runs low.")
                ) {
                    SettingsRow(symbol: "battery.50", title: L("Battery charge")) {
                        Picker(L("Battery charge"), selection: $preferences.batteryMenuBarThreshold) {
                            ForEach(BatteryMenuBar.thresholds, id: \.self) { Text(Self.thresholdTitle($0)).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
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
}

/// How the menu bar readout is drawn.
struct MenuBarAppearancePage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .menuBarAppearance) {
            SettingsGroup(title: L("Preview")) { MenuBarPreview(preferences: preferences) }

            SettingsGroup {
                SettingsRow(symbol: "rectangle.split.3x1", title: L("Style")) {
                    Picker(L("Style"), selection: $preferences.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                RowDivider()
                SettingsRow(
                    symbol: "paintpalette.fill", title: L("Colored bars"),
                    subtitle: L("Bars start neutral and turn amber, orange and red as load rises")
                ) {
                    RowToggle(isOn: $preferences.coloredMenuBar)
                }
            }
        }
    }
}

/// The menu bar readout as it will look, drawn from fixed sample values, beside a mock clock.
struct MenuBarPreview: View {
    @ObservedObject var preferences: Preferences

    /// Only Macs with a battery offer the battery readout.
    static let hasBattery = BatteryProbe.read() != nil

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
        // Read as one element, with the sample readings, rather than as an image and a mock clock.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Menu bar preview"))
        .accessibilityValue(Format.statusTitle(
            Self.sample(batteryThreshold: threshold), metrics: preferences.menuBarMetrics, batteryThreshold: threshold
        ))
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
