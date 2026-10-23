import SysbarCore
import SwiftUI

/// One metric: title row with a short note at the right, the current value, and a graph of recent
/// history. Nothing is written under the graph. The graph takes the colour of the current load.
/// With `onTap` the whole card is a button.
struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    var unit = ""
    /// A few characters at the top right, such as the average or the total.
    var note = ""
    let series: [Double]
    let capacity: Int
    let range: ClosedRange<Double>?
    let tint: Color
    /// Shown on hover, and read out by VoiceOver.
    var help = ""
    var onTap: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        if let onTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help(help)
        } else {
            content.help(help)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Sparkline(values: series, capacity: capacity, range: range, color: tint, height: 26)
                .revealOnAppear()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isHovering ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value)\(unit)")
        .accessibilityHint(onTap == nil ? "" : L("Opens details"))
    }
}
