import CoreGraphics

/// How tall a page of the panel is. Each page has the height of its own content; a page with a list
/// stops growing at `cap`, which the screen lowers, and the list scrolls beyond it.
public enum PageHeight {
    /// The tallest a page with a list gets.
    public static let cap: CGFloat = 420
    /// The least a page keeps, so a short screen never squeezes it to nothing.
    public static let floor: CGFloat = 160
    /// What the screen keeps from a page: the strip, the panel's inset and the dock or edge below.
    public static let screenMargin: CGFloat = 140

    /// The tallest a page may be on a screen whose usable height is `visibleHeight`.
    public static func limit(visibleHeight: CGFloat) -> CGFloat {
        max(min(cap, visibleHeight - screenMargin), floor)
    }

    /// A list's height: its rows (each `rowHeight` with `spacing` between, inside `padding` on both
    /// sides), but no more than `room`. An empty list is as tall as its padding.
    public static func list(rows: Int, rowHeight: CGFloat, spacing: CGFloat = 0, padding: CGFloat = 0, room: CGFloat) -> CGFloat {
        let count = CGFloat(max(rows, 0))
        let content = count * rowHeight + max(count - 1, 0) * spacing + 2 * padding
        return min(content, max(room, 0))
    }
}
