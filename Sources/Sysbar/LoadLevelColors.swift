import AppKit
import SysbarCore
import SwiftUI

/// Colours that adapt to the light and dark appearance. They are resolved each time they are drawn,
/// so the popover, the settings window and the colour menu bar image all follow the system theme
/// without any extra work.
private func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let value = isDark ? dark : light
        return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
    }
}

extension LoadLevel {
    /// The menu bar keeps the label colour while a load is quiet, so it looks like an ordinary
    /// uncoloured bar; only a load worth noticing turns amber, orange and red. Each is drawn
    /// separately for the light and the dark appearance.
    var nsColor: NSColor {
        switch self {
        case .low: .labelColor
        case .moderate: Palette.moderate
        case .high: Palette.high
        case .critical: Palette.critical
        }
    }

    var color: Color { Color(nsColor) }

    /// The same scale for a card's graph, with a neutral grey in place of the label colour so a
    /// quiet graph sits behind its value instead of matching the text.
    var cardColor: Color {
        switch self {
        case .low: Color(adaptive(light: (0.43, 0.43, 0.46), dark: (0.66, 0.66, 0.69)))
        case .moderate: Color(Palette.moderate)
        case .high: Color(Palette.high)
        case .critical: Color(Palette.critical)
        }
    }

    var title: String {
        switch self {
        case .low: L("Low")
        case .moderate: L("Moderate")
        case .high: L("High")
        case .critical: L("Critical")
        }
    }
}

/// The warning end of the load scale, shared by the menu bar and the cards. The light values are
/// deep enough to read on a pale card or menu bar; the dark ones stay bright on a dark background.
private enum Palette {
    static let moderate = adaptive(light: (0.62, 0.43, 0.02), dark: (0.88, 0.70, 0.32))
    static let high = adaptive(light: (0.72, 0.34, 0.10), dark: (0.91, 0.53, 0.29))
    static let critical = adaptive(light: (0.79, 0.19, 0.19), dark: (0.92, 0.42, 0.38))
}

/// The two series of a card that shows both, told apart by weight, not by hue: the stronger line
/// is what comes in, the fainter one what goes out. The direction is also given by the arrow and by
/// which side of the zero line it is on. They set the text too, so each is legible on its background.
enum FlowColors {
    /// What comes in (read, download) and what the Mac itself uses.
    static let inbound = Color(adaptive(light: (0.15, 0.15, 0.17), dark: (0.90, 0.90, 0.92)))
    static let draw = inbound
    /// What goes out: write, upload. Dimmer than the inbound line, but still readable as text.
    static let outbound = Color(adaptive(light: (0.36, 0.36, 0.39), dark: (0.72, 0.72, 0.75)))
    /// What goes into the battery: the one green on the cards. It also marks the charging bolt.
    static let charge = Color(adaptive(light: (0.12, 0.50, 0.28), dark: (0.38, 0.80, 0.52)))
}
