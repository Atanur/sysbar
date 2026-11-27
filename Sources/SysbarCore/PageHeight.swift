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

    /// The height of the menu bar popover for a page that wants `wanted`, in `room` below the menu bar
    /// item: as tall as the page, but never past the room, nor below the floor.
    public static func popoverHeight(wanted: CGFloat, room: CGFloat) -> CGFloat {
        max(min(wanted, room), floor)
    }

    /// A list's height: its rows (each `rowHeight` with `spacing` between, inside `padding` on both
    /// sides), but no more than `room`. An empty list is as tall as its padding. Capped, it ends on a
    /// whole row (with the padding above it only), so no row is cut in half at the bottom; the list
    /// scrolls for the rest. Room for less than one row is all it gets.
    public static func list(rows: Int, rowHeight: CGFloat, spacing: CGFloat = 0, padding: CGFloat = 0, room: CGFloat) -> CGFloat {
        let count = CGFloat(max(rows, 0))
        let content = count * rowHeight + max(count - 1, 0) * spacing + 2 * padding
        let room = max(room, 0)
        if content <= room { return content }
        let fitting = ((room - padding + spacing) / (rowHeight + spacing)).rounded(.down)
        guard fitting >= 1 else { return room }
        return padding + fitting * rowHeight + (fitting - 1) * spacing
    }
}
