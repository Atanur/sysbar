import AppKit
import SysbarCore

/// Draws the stash picker's tiles in a flipped view: one tile per stash with its colour dot and a dashed one for
/// a new stash. The island draws them below its closed row while files are dragged.
enum ShelfPickerTiles {
    static func draw(_ layout: ShelfPickerLayout, stashes: [ShelfStash], hovered: ShelfPickerLayout.Target?) {
        for tile in layout.tiles {
            draw(tile, stashes: stashes, isHovered: hovered == tile.target)
        }
    }

    private static func draw(_ tile: ShelfPickerLayout.Tile, stashes: [ShelfStash], isHovered: Bool) {
        let rect = tile.frame
        let path = NSBezierPath(continuousRoundedRect: rect.insetBy(dx: 0.75, dy: 0.75), radius: 10)
        path.lineWidth = 1.5
        let title: String
        // The colour marks the stash by its dot only; the tile itself is neutral.
        var badge: NSColor = .white
        var count: Int?
        switch tile.target {
        case .stash(let id):
            let stash = stashes.first { $0.id == id }
            title = stash?.displayName ?? ""
            badge = StashStyle.nsColor(stash?.color ?? 0)
            count = stash?.items.count
        case .newStash:
            title = L("New Stash")
            path.setLineDash([5, 3], count: 2, phase: 0)
        }
        NSColor.white.withAlphaComponent(isHovered ? 0.26 : 0.1).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(isHovered ? 0.8 : 0.35).setStroke()
        path.stroke()

        let marker = NSRect(x: rect.minX + 12, y: rect.midY - 4.5, width: 9, height: 9)
        if case .newStash = tile.target {
            let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .bold).applying(.init(paletteColors: [.white])))
            plus?.draw(in: marker.insetBy(dx: -1, dy: -1))
        } else {
            badge.setFill()
            NSBezierPath(ovalIn: marker).fill()
        }
        let countText = count.map { NSAttributedString(string: "\($0)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]) }
        let countWidth = (countText?.size().width ?? 0) + (countText == nil ? 0 : 8)
        let nameRect = NSRect(x: marker.maxX + 8, y: rect.midY - 8, width: rect.maxX - marker.maxX - 20 - countWidth, height: 16)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
        ]).draw(in: nameRect)
        if let countText {
            countText.draw(at: NSPoint(x: rect.maxX - 12 - countText.size().width, y: rect.midY - countText.size().height / 2))
        }
    }
}
