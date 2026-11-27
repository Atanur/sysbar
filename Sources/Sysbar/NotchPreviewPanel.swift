import SysbarCore
import SwiftUI

/// The open island's System page as a still picture for the settings preview: the header row, the
/// cards the Window page has on, and a hint of the top apps, all from fixed sample data. It has the
/// panel's real size and spacing, so it can be scaled with the rest of the preview.
struct NotchPreviewPanel: View {
    let preferences: Preferences
    /// The side of the strip's icons, which the header's buttons share.
    let iconSide: CGFloat

    private static let cardHeight: CGFloat = 96
    private static let cardSpacing: CGFloat = 8
    private static let topAppsHeight: CGFloat = 54
    private static let samples = 40

    /// The cards shown, in the user's order, at most two rows of three.
    private var metrics: [MenuBarMetric] { Array(preferences.visibleCards.prefix(6)) }

    private static func rows(_ count: Int) -> Int {
        count == 0 ? 0 : (count + CardLayout.wideColumns(forCount: count) - 1) / CardLayout.wideColumns(forCount: count)
    }

    /// The panel's height under the strip, as the real one adds it up.
    static func height(preferences: Preferences, iconSide: CGFloat) -> CGFloat {
        let rows = rows(min(preferences.visibleCards.count, 6))
        let cards = CGFloat(rows) * cardHeight + CGFloat(max(rows - 1, 0)) * cardSpacing
        let apps = preferences.showsApps ? topAppsHeight : 0
        let body = [cards, apps].filter { $0 > 0 }
        let content = body.reduce(0, +) + CGFloat(max(body.count - 1, 0)) * 12
        return 8 + max(iconSide, 24) + (body.isEmpty ? 0 : 8 + content) + PopoverView.wideInset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !metrics.isEmpty || preferences.showsApps {
                VStack(alignment: .leading, spacing: 12) {
                    cards
                    if preferences.showsApps { topApps }
                }
            }
        }
        .padding(.horizontal, PopoverView.wideInset)
        .padding(.top, 8)
        .padding(.bottom, PopoverView.wideInset)
        .frame(width: PopoverView.wideWidth, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                tab(preferences.thisMacTitle, selected: true)
                tab("Mac mini", selected: false, live: true)
            }
            Spacer(minLength: 0)
            if preferences.showsFanButton { glyph("fan") }
            if preferences.showsKeepAwakeButton { glyph("cup.and.saucer") }
            glyph("gearshape")
        }
        .frame(minHeight: iconSide)
    }

    private func tab(_ title: String, selected: Bool, live: Bool = false) -> some View {
        HStack(spacing: 5) {
            if live { Circle().fill(LoadLevel.low.color).frame(width: 6, height: 6) }
            Text(title)
        }
        .font(.callout.weight(selected ? .semibold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background { if selected { Capsule().fill(Color.primary.opacity(0.12)) } }
        .foregroundStyle(selected ? Color.primary : Color.secondary)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: iconSide * 0.55))
            .foregroundStyle(.secondary)
            .frame(width: iconSide, height: iconSide)
    }

    // MARK: Cards

    private var cards: some View {
        let columns = CardLayout.wideColumns(forCount: metrics.count)
        let rows = stride(from: 0, to: metrics.count, by: columns).map { Array(metrics[$0..<min($0 + columns, metrics.count)]) }
        return VStack(spacing: Self.cardSpacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Self.cardSpacing) {
                    ForEach(rows[row], id: \.self) { card($0) }
                    // A short last row keeps its cards the width of the others.
                    ForEach(0..<(columns - rows[row].count), id: \.self) { _ in Color.clear }
                }
                .frame(height: Self.cardHeight)
            }
        }
    }

    private func card(_ metric: MenuBarMetric) -> some View {
        let sample = Self.sample(metric)
        return MetricCard(
            title: metric.title, symbol: metric.symbol, value: sample.value, unit: sample.unit, note: sample.note,
            series: sample.series, secondary: sample.secondary, readouts: sample.readouts,
            capacity: Self.samples, range: sample.range, tint: sample.tint, fillsHeight: true, revealsGraph: false
        )
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: L("Top apps"), icon: { Image(systemName: "list.bullet") }) { EmptyView() }
            appRow("Safari", "14%")
            appRow("Xcode", "9%")
        }
        .cardChrome()
        .frame(height: Self.topAppsHeight)
    }

    private func appRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.caption)
    }

    // MARK: Sample data

    private struct Sample {
        var value: String
        var unit = ""
        var note = ""
        var series: [Double]
        var secondary: [Double]?
        var readouts: [Readout] = []
        var range: ClosedRange<Double>? = 0...1
        var tint: Color = FlowColors.inbound
    }

    /// A smooth, repeatable curve around `base`, so the graphs look alive but never change.
    private static func wave(_ base: Double, swing: Double, phase: Double) -> [Double] {
        (0..<samples).map { index in
            let x = Double(index)
            return min(max(base + swing * sin(x / 4 + phase) + swing / 2 * sin(x / 1.7 + 2 * phase), 0.02), 1)
        }
    }

    private static func sample(_ metric: MenuBarMetric) -> Sample {
        switch metric {
        case .cpu:
            Sample(value: "23", unit: "%", note: "52°C", series: wave(0.3, swing: 0.14, phase: 0), tint: LoadLevel.low.cardColor)
        case .gpu:
            Sample(value: "62", unit: "%", series: wave(0.5, swing: 0.2, phase: 1), tint: LoadLevel.moderate.cardColor)
        case .memory:
            Sample(value: "11.2", unit: "GB", note: "16 GB", series: wave(0.66, swing: 0.05, phase: 2), tint: LoadLevel.low.cardColor)
        case .power:
            Sample(value: "8.6", unit: "W", series: wave(0.3, swing: 0.12, phase: 3), range: nil, tint: FlowColors.draw)
        case .disk:
            Sample(
                value: "", series: wave(0.3, swing: 0.2, phase: 4), secondary: wave(0.12, swing: 0.08, phase: 5),
                readouts: [Readout(text: "↓1.2 MB/s", color: FlowColors.inbound), Readout(text: "↑0.3", color: FlowColors.outbound)],
                range: nil
            )
        case .network:
            Sample(
                value: "", note: L("Wi-Fi"), series: wave(0.25, swing: 0.15, phase: 6), secondary: wave(0.1, swing: 0.06, phase: 7),
                readouts: [Readout(text: "↓48 KB/s", color: FlowColors.inbound), Readout(text: "↑9", color: FlowColors.outbound)],
                range: nil
            )
        }
    }
}
