import CoreGraphics

/// One connected display, as far as choosing where the island goes needs to know.
public struct NotchDisplay: Equatable, Sendable {
    public let id: UInt32
    public let isBuiltIn: Bool

    public init(id: UInt32, isBuiltIn: Bool) {
        self.id = id
        self.isBuiltIn = isBuiltIn
    }
}

/// Which displays get an island when Sysbar is at the top of the screen.
public enum NotchDisplayChoice: String, CaseIterable, Sendable {
    /// The Mac's own display, where the notch is.
    case builtIn
    /// Every display has its own island.
    case all
    /// The display that has the active menu bar, which follows the focus from one to the next.
    case active

    /// The ids of the displays that show an island, in `displays`' order. A choice that has nothing to
    /// go by (no built-in display, as on a desktop Mac or with the lid closed; an active display that
    /// has just been unplugged) falls back to the primary display, so the island never disappears.
    public func select(from displays: [NotchDisplay], primary: UInt32?, active: UInt32?) -> [UInt32] {
        guard let first = displays.first else { return [] }
        let known = Set(displays.map(\.id))
        let fallback = primary.flatMap { known.contains($0) ? $0 : nil } ?? first.id
        switch self {
        case .builtIn:
            let own = displays.filter(\.isBuiltIn).map(\.id)
            return own.isEmpty ? [fallback] : own
        case .all:
            return displays.map(\.id)
        case .active:
            return [active.flatMap { known.contains($0) ? $0 : nil } ?? fallback]
        }
    }
}

/// What fills the island behind its readouts and its open panel.
public enum NotchBackground: String, CaseIterable, Sendable {
    /// Black around the notch, which it merges with, and glass on a display without one.
    case automatic
    case black
    case glass
    /// No fill at all; the content has a faint shadow so it stays legible on the desktop.
    case transparent

    public enum Fill: Equatable, Sendable {
        case black, glass, clear

        /// Black is the one fill that is dark whatever is behind it, so it needs the dark look.
        public var isDark: Bool { self == .black }
    }

    public func fill(for shape: NotchGeometry.Shape) -> Fill {
        switch self {
        case .automatic: shape == .notch ? .black : .glass
        case .black: .black
        case .glass: .glass
        case .transparent: .clear
        }
    }
}

/// Whether the island's readouts and icons keep their colours.
public enum NotchIconStyle: String, CaseIterable, Sendable {
    case colored, monochrome
}

/// How big the readouts and feature icons are, relative to the default.
public enum NotchIconSize: String, CaseIterable, Sendable {
    case small, medium, large

    public var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.15
        }
    }
}

/// How the closed island opens.
public enum NotchOpening: String, CaseIterable, Sendable {
    /// Resting the pointer on it.
    case hover
    /// Only a click.
    case click
}
