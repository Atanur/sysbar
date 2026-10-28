import SysbarCore
import SwiftUI

/// A plain, single-colour symbol in a fixed square, so rows and headers line up.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.68, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A settings page: a header with a tile, title, one line of description and an optional control
/// at the right, then content.
struct SettingsPageScaffold<Content: View, Accessory: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    /// Whatever, when it changes, reshapes the page (rows appearing, a group replaced), so that
    /// change is animated.
    var animating: AnyHashable = 0
    let accessory: Accessory
    let content: Content

    init(
        symbol: String, title: String, subtitle: String, animating: AnyHashable = 0,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.animating = animating
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    IconTile(symbol: symbol, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title2.weight(.semibold)).lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    accessory
                }
                content
            }
            .motion(.snappy(duration: 0.25), value: animating)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

extension SettingsPageScaffold where Accessory == EmptyView {
    /// A fixed page, with the page's own title, description and symbol.
    init(page: SettingsPage, animating: AnyHashable = 0, @ViewBuilder content: () -> Content) {
        self.init(
            symbol: page.symbol, title: page.title, subtitle: page.subtitle, animating: animating,
            accessory: { EmptyView() }, content: content
        )
    }
}

/// A titled card of rows, with an optional line of explanation under it.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .settingsCard()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One line in a group: optional tile, title, optional subtitle, and a control at the right.
struct SettingsRow<Accessory: View>: View {
    var symbol: String?
    let title: String
    var subtitle: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { IconTile(symbol: symbol, size: 24) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory.environment(\.settingsRowTitle, title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }
}

extension EnvironmentValues {
    /// The title of the row a control sits in. A row's switch or slider has no visible label of its
    /// own, so it takes this one as its accessibility name: VoiceOver says "Launch at login, switch",
    /// not just "switch".
    @Entry var settingsRowTitle = ""
}

/// Hairline between rows, starting after the tile.
struct RowDivider: View {
    var inset: CGFloat = 46

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// A compact switch for the right side of a row.
struct RowToggle: View {
    @Binding var isOn: Bool
    @Environment(\.settingsRowTitle) private var title

    var body: some View {
        Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// A seconds slider with its value beside it. With `debounce`, the bound value is written only after
/// the slider has rested that long, so dragging does not restart sampling at every step; the label
/// follows the thumb immediately either way.
struct IntervalSlider: View {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let step: TimeInterval
    /// Cleans up a slider value (clamping, float noise) before it is stored.
    let normalize: (TimeInterval) -> TimeInterval
    var debounce: Duration?

    @State private var draft: TimeInterval?
    @State private var pending: Task<Void, Never>?
    @Environment(\.settingsRowTitle) private var title

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { draft ?? value }, set: update), in: range, step: step)
                .frame(width: 180)
                .accessibilityLabel(title)
                .accessibilityValue(L("%@ s", SamplingInterval.text(draft ?? value)))
            Text(L("%@ s", SamplingInterval.text(draft ?? value)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .onDisappear { commitPending() }
    }

    private func update(_ raw: TimeInterval) {
        let cleaned = normalize(raw)
        guard let debounce else {
            value = cleaned
            return
        }
        draft = cleaned
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            value = cleaned
            draft = nil
        }
    }

    /// Leaving the page must not lose a value that was still waiting out the debounce.
    private func commitPending() {
        pending?.cancel()
        if let draft { value = draft }
        draft = nil
    }
}

extension View {
    /// The card surface used by groups and tiles: a raised fill with a hairline edge.
    func settingsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

/// One row per metric in the given order. A row is dragged by its handle onto another to take its
/// place; the context menu and the accessibility actions move it one step instead.
struct ArrangedMetricRows<Accessory: View>: View {
    let order: [MenuBarMetric]
    let move: (MenuBarMetric, MenuBarMetric) -> Void
    let step: (MenuBarMetric, Int) -> Void
    @ViewBuilder let accessory: (MenuBarMetric) -> Accessory

    var body: some View {
        ForEach(Array(order.enumerated()), id: \.element) { index, metric in
            if index > 0 { RowDivider() }
            SettingsRow(symbol: metric.symbol, title: metric.displayName) {
                accessory(metric)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .help(L("Drag to change the order"))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .draggable(metric.rawValue) {
                Text(metric.displayName).padding(.horizontal, 10).padding(.vertical, 6)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dropped = items.first.flatMap(MenuBarMetric.init(rawValue:)) else { return false }
                withAnimation(.snappy) { move(dropped, metric) }
                return true
            }
            .contextMenu {
                Button(L("Move up")) { withAnimation(.snappy) { step(metric, -1) } }
                    .disabled(index == 0)
                Button(L("Move down")) { withAnimation(.snappy) { step(metric, 1) } }
                    .disabled(index == order.count - 1)
            }
            .accessibilityAction(named: L("Move up")) { step(metric, -1) }
            .accessibilityAction(named: L("Move down")) { step(metric, 1) }
        }
    }
}

extension MenuBarMetric {
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .power: "bolt.fill"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        }
    }
}

extension AppSortKey {
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "display"
        case .power: "bolt.fill"
        }
    }
}
