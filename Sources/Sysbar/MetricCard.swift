import SysbarCore
import SwiftUI

/// One of two figures shown side by side in a card's value row, in the colour of its graph line.
struct Readout {
    let text: String
    let color: Color
}

/// A small symbol after a card's note, such as the green bolt while the battery charges.
struct NoteSymbol {
    let systemName: String
    let color: Color
    /// Read by VoiceOver in place of the symbol's own name.
    let label: String
}

/// One metric: title row with a short note at the right, the current value, and a graph of recent
/// history. Nothing is written under the graph. The graph takes the colour of the current load.
/// With `onTap` the whole card is a button.
///
/// A card with two figures (read and write, download and upload, draw and charge) shows both in
/// `readouts`, smaller than a single value, and draws `secondary` below the zero line.
struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    var unit = ""
    /// What VoiceOver says for the value when the drawn text does not read well, such as arrows.
    var spokenValue: String?
    /// A few characters at the top right, such as the average or the total.
    var note = ""
    var noteColor: Color?
    var noteSymbol: NoteSymbol?
    let series: [Double]
    /// A second series, drawn mirrored below the first.
    var secondary: [Double]?
    var secondaryTint: Color = FlowColors.outbound
    var readouts: [Readout] = []
    let capacity: Int
    let range: ClosedRange<Double>?
    let tint: Color
    /// Shown on hover, and read out by VoiceOver.
    var help = ""
    var onTap: (() -> Void)?

    @State private var isHovering = false

    private static let graphHeight: CGFloat = 32
    /// Keeps cards with one large value and cards with two smaller ones the same height.
    private static let valueRowHeight: CGFloat = 27

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
                HStack(spacing: 3) {
                    if !note.isEmpty { Text(note) }
                    if let noteSymbol {
                        Image(systemName: noteSymbol.systemName)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(noteSymbol.color)
                            .accessibilityLabel(noteSymbol.label)
                    }
                }
                .font(.caption2)
                .foregroundStyle(noteColor ?? .secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            valueRow
            graph.revealOnAppear()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isHovering ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // One element per card: its title, then the value and the note in words.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            [spokenValue ?? "\(value)\(unit)", note, noteSymbol?.label ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        )
        .accessibilityHint(onTap == nil ? "" : L("Opens details"))
    }

    @ViewBuilder
    private var valueRow: some View {
        if readouts.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(readouts.indices, id: \.self) { index in
                    Text(readouts[index].text)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(readouts[index].color)
                }
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minHeight: Self.valueRowHeight, alignment: .leading)
        }
    }

    @ViewBuilder
    private var graph: some View {
        if let secondary {
            MirroredSparkline(
                upper: series, lower: secondary, capacity: capacity,
                upperColor: tint, lowerColor: secondaryTint, height: Self.graphHeight
            )
        } else {
            Sparkline(values: series, capacity: capacity, range: range, color: tint, height: Self.graphHeight)
        }
    }
}
