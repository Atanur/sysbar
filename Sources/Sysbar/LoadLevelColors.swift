import AppKit
import SysbarCore
import SwiftUI

/// Muted, low-saturation colours that adapt to the light and dark appearance. They are resolved
/// each time they are drawn, so the popover, the settings window and the colour menu bar image
/// all follow the system theme without any extra work.
private func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let value = isDark ? dark : light
        return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
    }
}

extension LoadLevel {
    var nsColor: NSColor {
        switch self {
        case .low: Palette.low
        case .moderate: Palette.moderate
        case .high: Palette.high
        case .critical: Palette.critical
        }
    }

    var color: Color { Color(nsColor) }

    var title: String {
        switch self {
        case .low: L("Low")
        case .moderate: L("Moderate")
        case .high: L("High")
        case .critical: L("Critical")
        }
    }
}

private enum Palette {
    static let low = adaptive(light: (0.30, 0.56, 0.40), dark: (0.40, 0.64, 0.49))
    static let moderate = adaptive(light: (0.74, 0.60, 0.24), dark: (0.80, 0.67, 0.36))
    static let high = adaptive(light: (0.78, 0.48, 0.25), dark: (0.84, 0.56, 0.35))
    static let critical = adaptive(light: (0.70, 0.30, 0.28), dark: (0.80, 0.42, 0.40))
    static let activity = adaptive(light: (0.31, 0.52, 0.56), dark: (0.42, 0.62, 0.66))
}

/// Disk and network have no "too busy", so they use one calm hue instead of the load scale.
enum ActivityColors {
    static let nsColor = Palette.activity
    static let color = Color(Palette.activity)
}
