import SysbarCore
import SwiftUI

/// Which machine the popover is showing.
enum DeviceSelection: Hashable {
    case thisMac
    case remote(UUID)
}

@MainActor
final class PopoverViewModel: ObservableObject {
    @Published var history: BoundedHistory<Snapshot>
    /// Changes six times a second while animating. It is a separate object so only the cards
    /// that show it are recomputed per frame, not the whole popover and its apps table.
    let live = LiveReading()
    @Published var apps: [AppUsage] = []
    @Published var sort: AppSortKey = .cpu
    @Published var selection: DeviceSelection = .thisMac

    init(history: BoundedHistory<Snapshot>) {
        self.history = history
    }

}

/// The reading being animated towards the newest sample.
@MainActor
final class LiveReading: ObservableObject {
    @Published var snapshot: Snapshot?
}

/// Re-renders only its content when the live reading moves. The history's newest point is
/// replaced by the animated reading, so each graph's last point glides to the new value.
private struct LiveSamples<Content: View>: View {
    @ObservedObject var live: LiveReading
    let history: BoundedHistory<Snapshot>
    @ViewBuilder let content: ([Snapshot], Snapshot?) -> Content

    var body: some View {
        let items = history.items
        let samples = live.snapshot.map { items.isEmpty ? items : items.dropLast() + [$0] } ?? items
        content(samples, samples.last)
    }
}

struct PopoverView: View {
    static let width: CGFloat = 340

    @ObservedObject var model: PopoverViewModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var remote: RemoteMonitor
    @ObservedObject var updater: UpdateChecker
    let onSelect: (DeviceSelection) -> Void
    let onRetry: () -> Void
    /// Opens the settings window, on a given page or on whichever was shown last.
    let onSettings: (SettingsPage?) -> Void
    let onOpenDetails: (MenuBarMetric) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar
            if let release = updater.offered {
                UpdateBanner(updater: updater, release: release)
            }
            content
        }
        .padding(12)
        .frame(width: Self.width)
    }

    @ViewBuilder
    private var content: some View {
        if case .remote(let id) = model.selection, let device = preferences.device(id: id) {
            RemoteView(monitor: remote, cards: device.cards, temperatureUnit: preferences.temperatureUnit, rowLimit: preferences.appRows, onRetry: onRetry)
        } else {
            localContent
        }
    }

    // MARK: Top bar

    /// One row: a tab per machine on the left, the settings button on the right. The active tab
    /// has a solid background; the others are transparent until hovered.
    private var topBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tab(L("This Mac"), selection: .thisMac, status: nil)
                    ForEach(preferences.devices) { tab($0.name, selection: .remote($0.id), status: status(of: $0)) }
                }
            }
            Button { onSettings(nil) } label: {
                Image(systemName: "gearshape").font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("Settings"))
            .accessibilityLabel(L("Settings"))
        }
    }

    /// The session state of a remote device, shown as a dot on its tab; nil when it has none.
    private func status(of device: RemoteDevice) -> SessionStatus? {
        guard remote.deviceID == device.id else { return nil }
        switch remote.state {
        case .idle: return nil
        case .connecting: return .connecting
        case .live: return .live
        case .failed(let message): return .failed(message)
        }
    }

    private func tab(_ title: String, selection: DeviceSelection, status: SessionStatus?) -> some View {
        let isSelected = model.selection == selection
        return Button { onSelect(selection) } label: {
            HStack(spacing: 5) {
                if let status { SessionDot(status: status) }
                Text(title)
            }
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.primary.opacity(isSelected ? 0.12 : 0))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .help(status?.description ?? "")
        .accessibilityValue(status?.description ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: This Mac

    @ViewBuilder
    private var localContent: some View {
        if preferences.visibleCards.isEmpty && !preferences.showsApps {
            Text(L("Nothing is selected to show. Open the Window page in Settings."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if !preferences.visibleCards.isEmpty {
            LiveSamples(live: model.live, history: model.history) { samples, latest in
                LazyVGrid(columns: gridColumns(count: preferences.visibleCards.count), spacing: 8) {
                    ForEach(preferences.visibleCards, id: \.self) { card(for: $0, samples, latest) }
                }
            }
        }
        if preferences.showsApps {
            AppsTable(
                title: L("Top apps"),
                apps: model.apps, columns: preferences.appColumns, rowLimit: preferences.appRows,
                sort: model.sort
            ) { model.sort = $0 }
        }
    }

    private func gridColumns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: CardLayout.columns(forCount: count))
    }

    @ViewBuilder
    private func card(for metric: MenuBarMetric, _ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        switch metric {
        case .cpu: cpuCard(samples, latest)
        case .gpu: gpuCard(samples, latest)
        case .memory: memoryCard(samples, latest)
        case .power: powerCard(samples, latest)
        case .disk: diskCard(samples, latest)
        case .network: networkCard(samples, latest)
        }
    }

    private func cpuCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let series = samples.map(\.cpuUsage)
        return card(
            .cpu, title: L("CPU"), symbol: "cpu",
            value: latest.map { Format.percent($0.cpuUsage) } ?? "–",
            note: latest?.cpuTemperature.map { preferences.temperatureUnit.format(celsius: $0) } ?? "",
            help: statsHelp(series, Format.percent),
            series: series, range: 0...1,
            load: latest.map { LoadLevel(fraction: $0.cpuUsage) }
        )
    }

    private func gpuCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let series = samples.compactMap(\.gpuUsage)
        let watts = latest?.power?.gpu.map { " · \(Format.watts($0))" } ?? ""
        return card(
            .gpu, title: L("GPU"), symbol: "display",
            value: latest?.gpuUsage.map(Format.percent) ?? "–",
            note: "", help: statsHelp(series, Format.percent) + watts,
            series: series, range: 0...1,
            load: latest?.gpuUsage.map { LoadLevel(fraction: $0) }
        )
    }

    /// The corner shows the installed total; the pressure is in the tooltip and shows through the
    /// graph colour.
    private func memoryCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let tooltip = latest.map {
            L("%1$@ / %2$@ · Pressure %3$@",
              Format.gigabytes($0.memory.usedBytes), Format.gigabytes($0.memory.totalBytes), pressureText($0.memory.pressure))
        } ?? ""
        return card(
            .memory, title: L("Memory"), symbol: "memorychip",
            value: latest.map { Format.gigabytes($0.memory.usedBytes) } ?? "–",
            note: latest.map { Format.totalMemory($0.memory.totalBytes) } ?? "", help: tooltip,
            series: samples.map(\.memory.fraction), range: 0...1,
            load: latest.map { .memory(fraction: $0.memory.fraction, pressure: $0.memory.pressure) }
        )
    }

    private func powerCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let series = samples.compactMap(\.headlinePower)
        let battery = latest?.battery
        let note = PowerSummary.headline(battery: battery) ?? ""
        // The corner shows the battery state; adapter and wall details are in the tooltip.
        let tooltip = [
            PowerSummary.detail(battery: battery, systemPower: latest?.headlinePower),
            latest?.power.map(componentText),
        ].compactMap { $0 }.joined(separator: "\n")
        return card(
            .power, title: L("Power"), symbol: powerSymbol(battery),
            value: latest?.headlinePower.map(Format.watts) ?? "–",
            note: note, help: tooltip.isEmpty ? statsHelp(series, Format.watts) : tooltip,
            series: series, range: nil,
            load: latest?.headlinePower.map { LoadLevel(fraction: $0 / MenuBarReadouts.powerFullScaleWatts) }
        )
    }

    private func diskCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        card(
            .disk, title: L("Disk"), symbol: "internaldrive",
            value: latest?.disk.map { Format.rate($0.total) } ?? "–", unit: "/s",
            note: latest?.disk.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "",
            help: L("↓ Read · ↑ Write"),
            series: samples.compactMap { $0.disk?.total }, range: nil, load: nil
        )
    }

    private func networkCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        card(
            .network, title: L("Network"), symbol: "arrow.up.arrow.down",
            value: latest?.network.map { Format.rate($0.total) } ?? "–", unit: "/s",
            note: latest?.network.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "",
            help: L("↓ Download · ↑ Upload"),
            series: samples.compactMap { $0.network?.total }, range: nil, load: nil
        )
    }

    private func card(
        _ metric: MenuBarMetric, title: String, symbol: String, value: String, unit: String = "",
        note: String, help: String, series: [Double], range: ClosedRange<Double>?, load: LoadLevel?
    ) -> some View {
        MetricCard(
            title: title, symbol: symbol, value: value, unit: unit, note: note,
            series: series, capacity: model.history.capacity, range: range,
            tint: load?.color ?? ActivityColors.color,
            help: help.isEmpty ? L("Show details") : L("%@\nClick to show details", help),
            onTap: { onOpenDetails(metric) }
        )
    }

    // MARK: Helpers

    private func statsHelp(_ series: [Double], _ format: (Double) -> String) -> String {
        guard let stats = SeriesStats.of(series) else { return "" }
        return L("Peak %@", format(stats.max))
    }

    /// The icon follows the situation: a charge level on battery, a plug on an adapter.
    private func powerSymbol(_ battery: BatteryInfo?) -> String {
        guard let battery else { return "bolt" }
        if battery.isPluggedIn { return battery.isCharging ? "battery.100percent.bolt" : "powerplug" }
        switch battery.fraction {
        case 0.88...: return "battery.100percent"
        case 0.63...: return "battery.75percent"
        case 0.38...: return "battery.50percent"
        case 0.13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Only components with a trustworthy sensor are listed.
    private func componentText(_ power: PowerReading) -> String {
        [(L("CPU"), power.cpu), (L("GPU"), power.gpu), (L("ANE"), power.ane), (L("RAM"), power.ram)]
            .compactMap { name, watts in watts.map { L("%1$@ %2$@", name, Format.watts($0)) } }
            .joined(separator: " · ")
    }

    private func pressureText(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: L("normal")
        case .warning: L("high")
        case .critical: L("critical")
        }
    }
}

/// A remote session's state, as shown on its tab.
enum SessionStatus: Equatable {
    case connecting, live
    case failed(String)

    var color: Color {
        switch self {
        case .connecting: LoadLevel.moderate.color
        case .live: LoadLevel.low.color
        case .failed: LoadLevel.critical.color
        }
    }

    var description: String {
        switch self {
        case .connecting: L("Connecting…")
        case .live: L("Live")
        case .failed(let message): message
        }
    }
}

/// A small dot in the session's colour: a slow pulse while live, a faster one while connecting,
/// steady on failure. It uses the system's symbol effect, which the window server animates, so a
/// live dot does not make the popover redraw every frame. With Reduce Motion it stays still.
private struct SessionDot: View {
    let status: SessionStatus

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: status == .live)
            .symbolEffect(.pulse, options: .repeating.speed(1.6), isActive: status == .connecting)
            .accessibilityHidden(true)
    }
}
