import AppKit
import SysbarCore
import SwiftUI

/// This Mac's page, first in the devices section: welcome (first run only), what the Mac is, which
/// cards its tab shows and how often it is sampled. It can be renamed but not removed.
struct ThisMacPage: View {
    @ObservedObject var preferences: Preferences
    @StateObject private var details = ThisMacDetails()
    @State private var copied = false
    @State private var renaming = false

    private var info: SystemInfo { details.info }
    private var battery: BatteryInfo? { details.battery }
    private var model: String { info.modelName ?? info.modelIdentifier }

    var body: some View {
        SettingsPageScaffold(
            symbol: SettingsPage.thisMac.symbol, title: preferences.thisMacTitle, subtitle: subtitle,
            animating: AnyHashable(preferences.setupCompleted)
        ) {
            Button { renaming = true } label: {
                Label(L("Rename"), systemImage: "pencil")
            }
            .help(L("Its name is shown on its tab in the popover."))
        } content: {
            if !preferences.setupCompleted { welcome }
            aboutGroups
            cardsGroup
            samplingGroup
            SettingsGroup {
                SettingsRow(symbol: "doc.on.doc", title: L("Copy as text"), subtitle: L("The details of this Mac")) {
                    Button(copied ? L("Copied") : L("Copy"), action: copySummary)
                }
            }
        }
        .sheet(isPresented: $renaming) {
            ThisMacNameEditor(
                name: preferences.thisMacName,
                onSave: { name in
                    preferences.thisMacName = name
                    renaming = false
                },
                onCancel: { renaming = false }
            )
        }
    }

    /// The model, with "This Mac" in front once the Mac has a name of its own.
    private var subtitle: String {
        preferences.thisMacTitle == L("This Mac") ? model : "\(L("This Mac")) · \(model)"
    }

    @ViewBuilder
    private var aboutGroups: some View {
        SettingsGroup(title: L("System")) {
            infoRow("cpu", L("Chip"), info.chip)
            RowDivider()
            infoRow("laptopcomputer", L("Model"), model)
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
    }

    private var cardsGroup: some View {
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
    }

    private var samplingGroup: some View {
        SettingsGroup(
            title: L("Sampling"),
            footer: L("Faster refreshes use more CPU. Each graph holds 150 samples, so its time span follows the refresh rate. The apps table refreshes at most once a second.")
        ) {
            SettingsRow(
                symbol: "timer", title: L("Refresh rate"),
                subtitle: L("Graphs show %@", SamplingInterval.windowText(for: preferences.samplingInterval))
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
            "\(L("Model")): \(model) (\(info.modelIdentifier))",
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

/// What the page shows about this Mac, read once when the page opens rather than each time a
/// setting on it changes.
@MainActor
private final class ThisMacDetails: ObservableObject {
    let info = SystemInfoProbe.read()
    let battery = BatteryProbe.read()
}
