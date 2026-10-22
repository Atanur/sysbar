import AppKit
import SysbarCore

/// Draws the menu bar content as an image: per metric a thin vertical level bar and a number.
///
/// By default it is a template image, so the system tints it for the light or dark menu bar. In
/// colour mode it is drawn with real colours (bars coloured by load, text in the label colour).
/// Each slot is as wide as the metric's widest possible text, so the item never shifts as the
/// digits change, and numbers use the system font with tabular figures.
enum MenuBarImage {
    private static let height: CGFloat = 22
    private static let barWidth: CGFloat = 3
    private static let barHeight = CGFloat(MenuBarReadouts.barHeight)
    private static let barGap: CGFloat = 4
    private static let slotGap: CGFloat = 10
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)

    /// Changes only when something visible changes, so callers can skip redundant redraws.
    static func signature(for readouts: [MenuBarReadout], colored: Bool) -> String {
        let parts = readouts.map { readout in
            let pixels = Int((readout.level * barHeight).rounded())
            return "\(readout.metric.rawValue):\(readout.text):\(pixels):\(colored ? "\(String(describing: readout.load))" : "")"
        }
        return parts.joined(separator: "|") + (colored ? "#c" : "")
    }

    static func make(_ readouts: [MenuBarReadout], colored: Bool) -> NSImage {
        let slotTextWidths = readouts.map { max(width(of: $0.metric.widestText), width(of: $0.text)) }
        let slotWidths = slotTextWidths.map { barWidth + barGap + $0 }
        let totalWidth = slotWidths.reduce(0, +) + slotGap * CGFloat(max(readouts.count - 1, 0))

        let image = NSImage(size: NSSize(width: max(totalWidth, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (readout, slotWidth) in zip(readouts, slotWidths) {
                draw(readout, slotWidth: slotWidth, originX: x, colored: colored)
                x += slotWidth + slotGap
            }
            return true
        }
        image.isTemplate = !colored
        return image
    }

    private static func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func draw(_ readout: MenuBarReadout, slotWidth: CGFloat, originX: CGFloat, colored: Bool) {
        let textColor = colored ? NSColor.labelColor : NSColor.black
        let trackColor = colored ? NSColor.tertiaryLabelColor : NSColor.black.withAlphaComponent(0.28)
        let fillColor = colored ? (readout.load?.nsColor ?? ActivityColors.nsColor) : NSColor.black

        let barBottom = (height - barHeight) / 2
        trackColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: originX, y: barBottom, width: barWidth, height: barHeight),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        ).fill()

        let fillHeight = readout.level > 0 ? max(readout.level * barHeight, 1.5) : 0
        fillColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: originX, y: barBottom, width: barWidth, height: fillHeight),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        ).fill()

        let text = NSAttributedString(string: readout.text, attributes: [.font: font, .foregroundColor: textColor])
        let size = text.size()
        text.draw(at: NSPoint(x: originX + slotWidth - size.width, y: (height - size.height) / 2))
    }
}
