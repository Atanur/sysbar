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
    /// The tab shown; one that is not offered (see `PopoverView.sections`) shows the system.
    @Published var section: PopoverSection = .system
    /// The panel unfolded under the System page's top row; at most one is open.
    @Published var panel: PopoverPanel?

    init(history: BoundedHistory<Snapshot>) {
        self.history = history
    }

}

/// The tabs across the top, in order. The fans and keep awake are not tabs: they are buttons of the
/// System page, which unfold a panel under its top row.
@MainActor
enum PopoverSection: CaseIterable {
    case system, stash, clipboard

    var title: String {
        switch self {
        case .system: L("System")
        case .stash: Stash.title
        case .clipboard: L("Clipboard")
        }
    }

    var symbol: String {
        switch self {
        case .system: "gauge.with.dots.needle.33percent"
        case .stash: Stash.symbol
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// What the System page's top-row buttons unfold under it.
enum PopoverPanel: Equatable {
    case thermal
    case keepAwake
}

/// What a panel is asked to open on: a tab, and on the System page one of its panels already unfolded.
struct PanelTarget: Equatable {
    var section: PopoverSection
    var panel: PopoverPanel?
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
    /// Under the notch there is room to spread out sideways, but not as much as the screen allows: the
    /// panel is a popup hanging from the strip, three quarters as wide as it first was.
    static let wideWidth: CGFloat = 570
    /// What the wide panel keeps from its sides.
    static let wideInset: CGFloat = 12

    /// Lets the selected tab's background slide to the next one.
    @Namespace private var tabSelection

    @ObservedObject var model: PopoverViewModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var remote: RemoteMonitor
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var fans: FanController
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var helper: HelperConnection
    @ObservedObject var shelf: ShelfController
    let clipboard: ClipboardController
    /// The island's strip, whose icon size the settings button shares; used while `isWide`.
    @ObservedObject var topRow: NotchRowModel
    let onSelect: (DeviceSelection) -> Void
    let onRetry: () -> Void
    /// Opens the settings window, on a given page or on whichever was shown last.
    let onSettings: (SettingsPage?) -> Void
    let onOpenDetails: (MenuBarMetric) -> Void
    /// Closes the popover, before something it started appears on screen.
    let onClose: () -> Void
    /// Wide and short under the notch; narrow and tall from the menu bar.
    var isWide = false

    var body: some View {
        if isWide {
            // The strip above holds the ears, which are the tabs; this is the panel under it. Its first
            // row has the machine tabs (or the tab's name), the fan and keep-awake buttons and Settings,
            // and the page starts below. The panel is as tall as the page shown.
            VStack(alignment: .leading, spacing: 8) {
                wideHeader
                pages
            }
            .padding(.horizontal, Self.wideInset)
            .padding(.top, 8)
            .padding(.bottom, Self.wideInset)
            .frame(width: Self.wideWidth)
            .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
            .onPreferenceChange(PanelHeightKey.self) { topRow.report(height: $0) }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if showsSectionBar { sectionBar }
                pages
            }
            .padding(12)
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// The tab's page, with its own height: what is shown replaces the last page, and the window
    /// follows the difference. A page with a list stops at `pageLimit` and scrolls.
    @ViewBuilder
    private var pages: some View {
        switch shownSection {
        case .system: systemContent
        case .stash: StashPage(shelf: shelf, preferences: preferences, isWide: isWide, maxHeight: pageLimit, onClose: onClose)
        case .clipboard: ClipboardPage(clipboard: clipboard, preferences: preferences, isWide: isWide, maxHeight: pageLimit, onClose: onClose)
        }
    }

    /// The tallest a page with a list gets: the cap, lowered on a short screen.
    private var pageLimit: CGFloat {
        PageHeight.limit(visibleHeight: NSScreen.main?.visibleFrame.height ?? PageHeight.cap + PageHeight.screenMargin)
    }

    private var systemContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isWide { topBar }
            controlPanel
            if let release = updater.offered {
                UpdateBanner(updater: updater, release: release)
            }
            content
        }
    }

    /// The tabs on offer: the System page, the stash while it is on, and the clipboard while its
    /// history is on.
    private var sections: [PopoverSection] {
        var sections: [PopoverSection] = [.system]
        if preferences.shelfEnabled { sections.append(.stash) }
        if preferences.clipboardHistoryEnabled { sections.append(.clipboard) }
        return sections
    }

    /// A tab that has gone away, such as the stash once it is turned off, shows the system instead.
    private var shownSection: PopoverSection {
        sections.contains(model.section) ? model.section : .system
    }

    private var showsSectionBar: Bool { sections.count > 1 }

    /// The fan button is for Macs that can read their temperatures, and for this Mac only.
    private var showsFanButton: Bool {
        model.selection == .thisMac && preferences.showsFanButton && fanReading != nil
    }

    private var showsKeepAwakeButton: Bool {
        model.selection == .thisMac && preferences.showsKeepAwakeButton
    }

    // MARK: Tabs

    /// The tabs, with Settings at the end. Only the selected one keeps its word, so the tabs fit, and
    /// the others are icons with the word as their tooltip and spoken label.
    private var sectionBar: some View {
        HStack(spacing: 4) {
            ForEach(sections, id: \.self) { sectionTab($0) }
            Spacer(minLength: 8)
            settingsButton
        }
        .motion(.snappy(duration: 0.22), value: model.section)
    }

    /// The panel's first row under the notch: on the System page the machine tabs, the buttons that
    /// unfold the fans and keep awake, and Settings at the right end, as tall as an icon of the strip;
    /// on another page the name of the tab and Settings.
    private var wideHeader: some View {
        HStack(spacing: 8) {
            if shownSection == .system {
                machineTabs
                controlButtons
            } else {
                Text(shownSection.title).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                Spacer(minLength: 0)
            }
            settingsButton
        }
        .frame(minHeight: topRow.iconSide)
    }

    private func sectionTab(_ section: PopoverSection) -> some View {
        let isSelected = shownSection == section
        let badge = section == .stash && shelf.totalItemCount > 0 ? "\(shelf.totalItemCount)" : nil
        let showsTitle = isSelected
        return Button {
            model.section = section
        } label: {
            HStack(spacing: 5) {
                tabIcon(section).font(.callout)
                if showsTitle { Text(section.title) }
                if showsTitle, let badge {
                    Text(badge).font(.caption2.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
            }
            .font(Font.callout.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "section", in: tabSelection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(badge.map { L("%@ items", $0) } ?? "")
    }

    private func tabIcon(_ section: PopoverSection) -> some View {
        Image(systemName: section.symbol)
    }

    private var settingsButton: some View {
        // Under the notch it is as big as an ear's icon; in the menu bar's popover it is a plain button.
        let side: CGFloat? = isWide ? topRow.iconSide : nil
        return Button { onSettings(nil) } label: {
            Image(systemName: "gearshape")
                .font(side.map { Font.system(size: $0 * 0.55) } ?? .body)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .foregroundStyle(isWide ? Color.primary : Color.secondary)
        .help(L("Settings"))
        .accessibilityLabel(L("Settings"))
    }

    @ViewBuilder
    private var content: some View {
        if case .remote(let id) = model.selection, let device = preferences.device(id: id) {
            RemoteView(
                monitor: remote, cards: device.cards, layout: preferences.cardLayout,
                temperatureUnit: preferences.temperatureUnit, rowLimit: preferences.appRows, onRetry: onRetry
            )
        } else {
            localContent
        }
    }

    // MARK: Top bar

    /// One row: a tab per machine on the left, then the fan and keep-awake buttons, and the settings
    /// button on the right. The active tab has a solid background; the others are transparent until
    /// hovered.
    private var topBar: some View {
        HStack(spacing: 8) {
            machineTabs
            controlButtons
            // With the tabs shown, Settings sits at their end instead.
            if !showsSectionBar { settingsButton }
        }
    }

    // MARK: Fans and keep awake

    /// The buttons that unfold the fans and keep awake, left of Settings: for this Mac only, and each
    /// unless hidden in Settings.
    @ViewBuilder
    private var controlButtons: some View {
        // As big as an icon of the strip under the notch; a plain button in the menu bar's popover.
        let side = isWide ? topRow.iconSide : Self.buttonSide
        if showsFanButton {
            ThermalButton(
                assessment: assessment, unit: preferences.temperatureUnit, fanState: fanState,
                fanLoad: fanReading?.fanFraction ?? 0,
                isHeatWarning: assessment?.needsAttention(preferences.heatWarning) == true,
                isOpen: openPanel == .thermal, side: side
            ) { togglePanel(.thermal) }
        }
        if showsKeepAwakeButton {
            KeepAwakeButton(isActive: keepAwake.isActive, isOpen: openPanel == .keepAwake, side: side) {
                togglePanel(.keepAwake)
            }
        }
    }

    private static let buttonSide: CGFloat = 22

    /// The panel unfolded now, unless its button is not on offer (hidden in Settings, or another Mac shown).
    private var openPanel: PopoverPanel? {
        switch model.panel {
        case .thermal where showsFanButton: .thermal
        case .keepAwake where showsKeepAwakeButton: .keepAwake
        default: nil
        }
    }

    /// Unfolds a panel under the top row, or folds it again; opening one closes the other. The window
    /// follows the page's new height, and the panel is revealed as it grows.
    private func togglePanel(_ panel: PopoverPanel) {
        model.panel = model.panel == panel ? nil : panel
    }

    @ViewBuilder
    private var controlPanel: some View {
        switch openPanel {
        case .thermal:
            ThermalPanel(
                assessment: assessment, reading: fanReading,
                unit: preferences.temperatureUnit, fans: fans, helper: helper
            )
        case .keepAwake:
            KeepAwakePanel(keepAwake: keepAwake, helper: helper, preferences: preferences)
        case nil:
            EmptyView()
        }
    }

    private var machineTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                tab(preferences.thisMacTitle, selection: .thisMac, status: nil)
                ForEach(preferences.devices) { tab($0.name, selection: .remote($0.id), status: status(of: $0)) }
            }
            .motion(.snappy(duration: 0.22), value: model.selection)
        }
    }

    private var fanReading: ThermalReading? { model.history.items.last?.thermal }

    /// Stopped, automatic or manual, from the control mode and the newest speed reading.
    private var fanState: FanState {
        let speeds = fanReading?.fans.map(\.rpm) ?? []
        let average = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
        return FanState(isManual: fans.mode.isManual, rpm: average)
    }

    /// What is warming this Mac, read from the samples in the graphs.
    private var assessment: ThermalAssessment? {
        ThermalAssessment.assess(model.history.items)
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
                .background {
                    if isSelected {
                        Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "tab", in: tabSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
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
        Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: isWide ? CardLayout.wideColumns(forCount: count) : CardLayout.columns(forCount: count, mode: preferences.cardLayout)
        )
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
            note: latest?.gpuTemperature.map { preferences.temperatureUnit.format(celsius: $0) } ?? "",
            help: statsHelp(series, Format.percent) + watts,
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
        let content = PowerCardContent(
            samples: samples.map { PowerCardSample(headline: $0.headlinePower, battery: $0.battery, components: $0.power) }
        )
        return card(
            .power, title: L("Power"), symbol: content.symbol, value: content.value,
            note: content.note, noteSymbol: content.noteSymbol, help: content.help,
            series: content.series, secondary: content.secondary, secondaryTint: FlowColors.charge,
            readouts: content.readouts, range: nil, load: content.load, tint: content.tint
        )
    }

    /// The two figures of a card with a direction each: in (read, download) and out (write, upload).
    private func flowReadouts(_ io: IOThroughput?) -> [Readout] {
        guard let io else { return [] }
        return [
            Readout(text: "↓" + Format.rate(io.inbound), color: FlowColors.inbound),
            Readout(text: "↑" + Format.rate(io.outbound), color: FlowColors.outbound),
        ]
    }

    private func diskCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let flow = samples.compactMap(\.disk)
        let space = latest?.diskSpace
        let spaceHelp = space.map {
            L("%1$@ free of %2$@", Format.diskSize($0.availableBytes), Format.diskSize($0.totalBytes))
        }
        return card(
            .disk, title: L("Disk"), symbol: "internaldrive",
            value: latest?.disk.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "–", unit: "/s",
            spokenValue: latest?.disk.map { L("read %1$@, write %2$@", spokenRate($0.inbound), spokenRate($0.outbound)) },
            note: space.map { L("%@ free", Format.diskSize($0.availableBytes)) } ?? "",
            noteColor: space.flatMap(Self.noteColor(for:)),
            help: [L("↓ Read · ↑ Write"), spaceHelp].compactMap { $0 }.joined(separator: "\n"),
            series: flow.map(\.inbound), secondary: flow.map(\.outbound),
            readouts: flowReadouts(latest?.disk), range: nil, load: nil, tint: FlowColors.inbound
        )
    }

    /// The room left turns amber, then red, as the disk fills up; plenty of room stays quiet.
    private static func noteColor(for space: DiskSpace) -> Color? {
        switch space.level {
        case .plenty: nil
        case .low: LoadLevel.moderate.color
        case .critical: LoadLevel.critical.color
        }
    }

    private func networkCard(_ samples: [Snapshot], _ latest: Snapshot?) -> some View {
        let flow = samples.compactMap(\.network)
        return card(
            .network, title: L("Network"), symbol: "arrow.up.arrow.down",
            value: latest?.network.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "–", unit: "/s",
            spokenValue: latest?.network.map { L("download %1$@, upload %2$@", spokenRate($0.inbound), spokenRate($0.outbound)) },
            note: latest?.networkLink.flatMap(Self.name(of:)) ?? "",
            help: L("↓ Download · ↑ Upload"),
            series: flow.map(\.inbound), secondary: flow.map(\.outbound),
            readouts: flowReadouts(latest?.network), range: nil, load: nil, tint: FlowColors.inbound
        )
    }

    /// What to call the connection in a card's corner; nothing for tunnels and other links.
    private static func name(of link: NetworkLink) -> String? {
        switch link {
        case .wifi: L("Wi-Fi")
        case .ethernet: L("Ethernet")
        case .other: nil
        }
    }

    private func card(
        _ metric: MenuBarMetric, title: String, symbol: String, value: String, unit: String = "",
        spokenValue: String? = nil, note: String, noteColor: Color? = nil, noteSymbol: NoteSymbol? = nil, help: String, series: [Double],
        secondary: [Double]? = nil, secondaryTint: Color = FlowColors.outbound, readouts: [Readout] = [],
        range: ClosedRange<Double>?, load: LoadLevel?, tint: Color? = nil
    ) -> some View {
        MetricCard(
            title: title, symbol: symbol, value: value, unit: unit, spokenValue: spokenValue, note: note,
            noteColor: noteColor, noteSymbol: noteSymbol,
            series: series, secondary: secondary, secondaryTint: secondaryTint, readouts: readouts,
            capacity: model.history.capacity, range: range,
            tint: tint ?? load?.cardColor ?? FlowColors.inbound,
            help: help.isEmpty ? L("Show details") : L("%@\nClick to show details", help),
            onTap: { onOpenDetails(metric) }
        )
    }

    // MARK: Helpers

    private func statsHelp(_ series: [Double], _ format: (Double) -> String) -> String {
        guard let stats = SeriesStats.of(series) else { return "" }
        return L("Peak %@", format(stats.max))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, options: .repeating.speed(0.5), isActive: status == .live && !reduceMotion)
            .symbolEffect(.pulse, options: .repeating.speed(1.6), isActive: status == .connecting && !reduceMotion)
            .accessibilityHidden(true)
    }
}
