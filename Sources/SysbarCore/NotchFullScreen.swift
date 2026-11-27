import CoreGraphics

/// One window of the window list, as far as telling a full-screen display needs to know.
public struct FullScreenWindow: Equatable, Sendable {
    public let pid: Int32
    public let layer: Int
    /// In global display coordinates, origin at the top left, as the window list gives it.
    public let bounds: CGRect
    public let alpha: Double

    public init(pid: Int32, layer: Int, bounds: CGRect, alpha: Double) {
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }
}

/// One connected display, in the window list's coordinates.
public struct FullScreenDisplay: Equatable, Sendable {
    public let id: UInt32
    public let bounds: CGRect
    /// The display's current Space is a full-screen app's.
    public let inFullScreenSpace: Bool

    public init(id: UInt32, bounds: CGRect, inFullScreenSpace: Bool) {
        self.id = id
        self.bounds = bounds
        self.inFullScreenSpace = inFullScreenSpace
    }
}

/// Which displays are showing something full screen. A full-screen app's Space says so on its own,
/// but a game or a player that covers the display without making a Space does not, so a window of
/// another app that covers the whole display counts too. A window that only fills the space under
/// the menu bar, as a maximised one does, is not full screen, nor is the desktop (below layer 0),
/// a menu or an overlay (above it), a window that cannot be seen, or Sysbar's own.
public enum FullScreenDetection {
    /// A point of slack for windows a rounding short of the edge.
    private static let slack: CGFloat = 1

    public static func displays(windows: [FullScreenWindow], screens: [FullScreenDisplay], ownPID: Int32) -> Set<UInt32> {
        let covering = windows.filter { $0.pid != ownPID && $0.layer == 0 && $0.alpha > 0 }
        return Set(screens.filter { screen in
            screen.inFullScreenSpace
                || covering.contains { $0.bounds.contains(screen.bounds.insetBy(dx: slack, dy: slack)) }
        }.map(\.id))
    }
}

/// When the island is shown on a display that is not full screen.
public enum NotchIslandVisibility: String, CaseIterable, Sendable {
    /// Always there.
    case always
    /// Only while the pointer is on it.
    case pointer

    /// Whether the island hides until the pointer reaches it. Full screen always hides it.
    public func isConcealed(fullScreen: Bool) -> Bool {
        fullScreen || self == .pointer
    }
}

/// Where the pointer reveals an island that is hidden.
public enum IslandRevealZone {
    private static let sideSlack: CGFloat = 8
    private static let belowSlack: CGFloat = 2
    /// Past the top edge, where the pointer stops when pushed up, which is how a hidden menu bar is reached.
    private static let aboveSlack: CGFloat = 4

    /// The closed island's frame with a little slack, reaching up to the screen's top edge (AppKit
    /// coordinates, origin at the bottom left).
    public static func rect(strip: CGRect, screenTop: CGFloat) -> CGRect {
        let top = max(strip.maxY, screenTop) + aboveSlack
        let bottom = strip.minY - belowSlack
        return CGRect(x: strip.minX - sideSlack, y: bottom, width: strip.width + 2 * sideSlack, height: top - bottom)
    }
}
