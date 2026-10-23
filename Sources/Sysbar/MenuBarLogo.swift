import AppKit

/// The app icon's three level bars, drawn for the menu bar without the icon's background. They
/// have their own colours, so it is not a template image. Same colours as `scripts/make-icon.swift`.
enum MenuBarLogo {
    /// How full each bar is in the app icon.
    static let restingLevels: [Double] = [0.46, 0.78, 0.60]

    private static let barWidth: CGFloat = 3.5
    private static let barGap: CGFloat = 3
    private static let barHeight: CGFloat = 14
    private static let size = NSSize(width: barWidth * 3 + barGap * 2, height: barHeight)
    private static let barColors = [
        NSColor(srgbRed: 0.42, green: 0.67, blue: 0.51, alpha: 1),
        NSColor(srgbRed: 0.83, green: 0.69, blue: 0.38, alpha: 1),
        NSColor(srgbRed: 0.82, green: 0.45, blue: 0.43, alpha: 1),
    ]

    /// The bars, each filled to its level, from 0 to 1.
    static func image(levels: [Double] = restingLevels) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, level) in levels.prefix(3).enumerated() {
                barColors[index].setFill()
                NSBezierPath(
                    roundedRect: NSRect(
                        x: CGFloat(index) * (barWidth + barGap), y: 0,
                        width: barWidth, height: max(barHeight * level, barWidth)
                    ),
                    xRadius: barWidth / 2, yRadius: barWidth / 2
                ).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
