import AppKit
import SysbarCore

/// Draws the menu bar content as an image: per metric a thin vertical level bar and a number, and
/// for the battery a small battery shape filled to its charge.
///
/// By default it is a template image, so the system tints it for the light or dark menu bar. In
/// colour mode, or while the battery is shown (it always keeps its charge colour), it is drawn
/// with real colours and the text in the label colour. Each slot is as wide as its widest possible
/// text, so the item never shifts as the digits change, and numbers use tabular figures.
enum MenuBarImage {
    private static let height: CGFloat = 22
    private static let barWidth: CGFloat = 3
    private static let barHeight = CGFloat(MenuBarReadouts.barHeight)
    private static let barGap: CGFloat = 4
    private static let slotGap: CGFloat = 10
    private static let batteryBody = NSSize(width: 20, height: 10)
    private static let batteryCap = NSSize(width: 1.5, height: 4)
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)

    /// Changes only when something visible changes, so callers can skip redundant redraws.
    static func signature(for readouts: [MenuBarReadout], colored: Bool) -> String {
        let parts = readouts.map { readout in
            let pixels = Int((readout.level * barHeight).rounded())
            let showsColor = colored || readout.isAlwaysColored
            return "\(readout.slot.id):\(readout.text):\(pixels):\(showsColor ? "\(String(describing: readout.load))" : "")"
        }
        return parts.joined(separator: "|") + (colored ? "#c" : "")
    }

    static func make(_ readouts: [MenuBarReadout], colored: Bool) -> NSImage {
        let isTemplate = !keepsColors(readouts, colored: colored)
        let slotTextWidths = readouts.map { max(width(of: $0.slot.widestText), width(of: $0.text)) }
        let slotWidths = zip(readouts, slotTextWidths).map { graphicWidth(for: $0.0) + barGap + $0.1 }
        let totalWidth = slotWidths.reduce(0, +) + slotGap * CGFloat(max(readouts.count - 1, 0))

        let image = NSImage(size: NSSize(width: max(totalWidth, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (readout, slotWidth) in zip(readouts, slotWidths) {
                draw(readout, slotWidth: slotWidth, originX: x, colored: colored, isTemplate: isTemplate)
                x += slotWidth + slotGap
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    /// True when the image keeps its own colours, so a preview must not tint it.
    static func keepsColors(_ readouts: [MenuBarReadout], colored: Bool) -> Bool {
        colored || readouts.contains(where: \.isAlwaysColored)
    }

    private static func graphicWidth(for readout: MenuBarReadout) -> CGFloat {
        readout.slot == .battery ? batteryBody.width + batteryCap.width : barWidth
    }

    private static func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func draw(
        _ readout: MenuBarReadout, slotWidth: CGFloat, originX: CGFloat, colored: Bool, isTemplate: Bool
    ) {
        let ink = isTemplate ? NSColor.black : NSColor.labelColor
        let track = isTemplate ? NSColor.black.withAlphaComponent(0.28) : NSColor.tertiaryLabelColor
        let fill = (colored || readout.isAlwaysColored) ? (readout.load?.nsColor ?? ActivityColors.nsColor) : ink

        if readout.slot == .battery {
            drawBattery(level: readout.level, originX: originX, outline: track, fill: fill)
        } else {
            drawBar(level: readout.level, originX: originX, track: track, fill: fill)
        }

        let text = NSAttributedString(string: readout.text, attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        text.draw(at: NSPoint(x: originX + slotWidth - size.width, y: (height - size.height) / 2))
    }

    private static func drawBar(level: Double, originX: CGFloat, track: NSColor, fill: NSColor) {
        let barBottom = (height - barHeight) / 2
        track.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: originX, y: barBottom, width: barWidth, height: barHeight),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        ).fill()

        let fillHeight = level > 0 ? max(level * barHeight, 1.5) : 0
        fill.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: originX, y: barBottom, width: barWidth, height: fillHeight),
            xRadius: barWidth / 2, yRadius: barWidth / 2
        ).fill()
    }

    /// An outlined body with a small cap on the right, filled from the left to the charge.
    private static func drawBattery(level: Double, originX: CGFloat, outline: NSColor, fill: NSColor) {
        let body = NSRect(
            x: originX + 0.5, y: (height - batteryBody.height) / 2 + 0.5,
            width: batteryBody.width - 1, height: batteryBody.height - 1
        )
        outline.setStroke()
        let frame = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        frame.lineWidth = 1
        frame.stroke()

        outline.setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: body.maxX + 0.5, y: (height - batteryCap.height) / 2,
                width: batteryCap.width, height: batteryCap.height
            ),
            xRadius: 0.75, yRadius: 0.75
        ).fill()

        let inner = body.insetBy(dx: 1.5, dy: 1.5)
        let fillWidth = level > 0 ? max(inner.width * level, 1.5) : 0
        fill.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height),
            xRadius: 1.2, yRadius: 1.2
        ).fill()
    }
}
