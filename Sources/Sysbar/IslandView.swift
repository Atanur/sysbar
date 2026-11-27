import AppKit
import SwiftUI
import SysbarCore

/// One item in an ear as the island draws it: its place in the ear, the readouts' image when it is
/// the System item with bars to show, and whether it is there only while the island is open.
struct IslandEntry: Equatable {
    let core: NotchEarEntry
    var readouts: NSImage?
    var revealed = false
}

/// The island's drawing: a black shape that continues the notch, glass, or no fill at all; the items
/// of its two ears along the top (the readouts' bars and the feature icons, in the order and the ear
/// the user chose), which stay there when it opens and become its tabs; and below that strip, in a
/// panel that hangs from its bottom edge, the content while open or the stash tiles while files are
/// dragged. Strip and panel are one outline (see `IslandOutline`).
///
/// Black is dark whatever the system look, so its content is forced to the dark look. Glass and a
/// clear island follow the system look, which is what the desktop behind them is likely to follow; a
/// clear one also gives its content a faint shadow in the opposite tone, so it stays legible on any
/// wallpaper. While files are dragged the tiles need a dark ground, which a clear island then gets.
@MainActor
final class IslandView: NSView {
    private static let closedCorner: CGFloat = 10
    /// The open panel's bottom corners, concentric with the cards inside: their radius plus how far they
    /// sit from the panel's edge, as Apple nests rounded shapes.
    private static let openCorner: CGFloat = MetricCardStyle.corner + NotchGeometry.contentInset + PopoverView.wideInset
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onClick: () -> Void = {}
    var onRightClick: (NSView, NSPoint) -> Void = { _, _ in }
    /// A file drag came over the closed island, which then opens the picker.
    var onDragEntered: () -> Void = {}
    var onDragExited: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onDrop: ([URL], ShelfPickerLayout.Target) -> Bool = { _, _ in false }
    /// Whether files may be dropped on the picker at all, and whether a drag over the closed island opens it.
    var acceptsDrops = false
    var opensOnDrag = false

    private var shape: NotchGeometry.Shape = .notch
    /// What is drawn behind the content, with the picker's dark ground taken into account.
    private var fill: NotchBackground.Fill = .black
    /// Whether the island is a black shape, which is the only fill the window's shadow suits.
    var drawsBlack: Bool { fill == .black }
    /// The items' scale: the readouts' bars and the feature icons.
    private var scale: CGFloat = 1
    private var monochrome = false
    private let features: NotchFeatureModel
    private var header: CGFloat = 0
    private var notch: ClosedRange<CGFloat> = 0...0
    /// Where the strip is across the view: the closed row, which the panel hangs from.
    private var strip: ClosedRange<CGFloat> = 0...0
    private var open = false
    /// The island's size once open, which its content is laid out at while the island is still growing or shrinking.
    private var contentSize: NSSize = .zero
    private var leftEntries: [IslandEntry] = []
    private var rightEntries: [IslandEntry] = []
    /// What the readouts say, which VoiceOver reads on the System item.
    private var summary = ""
    /// The opacity of the content and of the items that show only while the island is open, which
    /// fade in and out with the sheet.
    private var contentAlpha: CGFloat = 1
    private var picker: ShelfPickerLayout?
    private var stashes: [ShelfStash] = []
    private var hovered: ShelfPickerLayout.Target? { didSet { overlay.hovered = hovered } }
    /// One view per item, made when it is first shown.
    private var itemViews: [NotchSlot: FirstMouseHostingView<NotchItemView>] = [:]
    private var itemStyles: [NotchSlot: NotchItemStyle] = [:]
    private let container = NSView()
    private let overlay = PickerOverlay()
    private var glass: NSView?
    /// Holds the glass and masks it with the outline.
    private var glassHost: NSView?
    private let glassMask = CAShapeLayer()
    private var cachedOutline: (key: OutlineKey, path: CGPath)?

    private struct OutlineKey: Equatable {
        let size: NSSize
        let shape: NotchGeometry.Shape
        let showsBody: Bool
        let strip: ClosedRange<CGFloat>
        let header: CGFloat
    }

    override var isFlipped: Bool { true }

    init(features: NotchFeatureModel) {
        self.features = features
        super.init(frame: .zero)
        // The shape starts as the notch, which `applyBackground` is never called for: the black island needs
        // the dark look from the first frame, or the panel's text follows a Light system.
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.masksToBounds = true
        container.wantsLayer = true
        // The ears stay above the content, so they take the clicks on the top row when it is open.
        addSubview(container)
        addSubview(overlay)
        registerForDraggedTypes([.fileURL, ShelfPasteboard.filenames])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func describe(_ description: String) {
        guard description != toolTip else { return }
        toolTip = description
        summary = description
    }

    func configure(
        geometry: NotchGeometry, header: CGFloat, notch: ClosedRange<CGFloat>, strip: ClosedRange<CGFloat>, left: [IslandEntry],
        right: [IslandEntry], open: Bool, contentSize: NSSize = .zero, picker: ShelfPickerLayout?, stashes: [ShelfStash],
        dragHint: Bool, look: NotchLook, scale: CGFloat
    ) {
        var fill = look.background.fill(for: geometry.shape)
        let tilesNeedDark = picker != nil
        if fill == .clear && tilesNeedDark { fill = .black }
        if shape != geometry.shape || self.fill != fill || fill == .glass && glass == nil { applyBackground(geometry.shape, fill) }
        self.header = header
        self.notch = notch
        self.strip = strip
        self.open = open
        self.contentSize = contentSize
        leftEntries = left
        rightEntries = right
        self.picker = picker
        self.stashes = stashes
        self.scale = scale
        if picker == nil { hovered = nil }
        syncItems(monochrome: look.iconStyle == .monochrome, scale: scale)
        // The tiles are white on a dark ground, which glass only is in the dark look.
        let dark = fill.isDark || tilesNeedDark
        appearance = dark ? NSAppearance(named: .darkAqua) : nil
        shadowsContent = fill == .clear
        updateShadows()
        overlay.configure(
            layout: picker, stashes: stashes, hint: dragHint && picker == nil && !open,
            corner: shape == .notch ? Self.closedCorner : header / 2, isNotch: shape == .notch
        )
        setAccessibilityElement(false)
        needsLayout = true
        needsDisplay = true
    }

    /// The ears' item views follow the entries: each is rebuilt only when how it looks changes, and
    /// one that is not in an ear is hidden.
    private func syncItems(monochrome: Bool, scale: CGFloat) {
        var shown = Set<NotchSlot>()
        for entry in leftEntries + rightEntries {
            let slot = entry.core.slot
            shown.insert(slot)
            let view = itemViews[slot] ?? makeItemView(slot)
            let style = NotchItemStyle(
                slot: slot, readouts: entry.readouts, scale: scale, monochrome: monochrome, open: open,
                summary: slot == .item(.system) ? summary : ""
            )
            if itemStyles[slot] != style {
                itemStyles[slot] = style
                view.rootView = NotchItemView(model: features, style: style)
            }
            view.isHidden = false
            view.alphaValue = entry.revealed ? contentAlpha : 1
        }
        for (slot, view) in itemViews where !shown.contains(slot) { view.isHidden = true }
    }

    private func makeItemView(_ slot: NotchSlot) -> FirstMouseHostingView<NotchItemView> {
        let view = FirstMouseHostingView(rootView: NotchItemView(model: features, style: NotchItemStyle(slot: slot)))
        view.sizingOptions = []
        view.wantsLayer = true
        // Under the picker's overlay, over the content.
        addSubview(view, positioned: .below, relativeTo: overlay)
        itemViews[slot] = view
        return view
    }

    private var shadowsContent = false

    /// A faint shadow behind a clear island's content, in the tone opposite to its text.
    private func updateShadows() {
        var shadow: NSShadow?
        if shadowsContent {
            let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            shadow = NSShadow()
            shadow?.shadowColor = isDark ? NSColor.black.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.7)
            shadow?.shadowBlurRadius = 3
            shadow?.shadowOffset = NSSize(width: 0, height: -0.5)
        }
        (Array(itemViews.values) + [container]).forEach { $0.shadow = shadow }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShadows()
    }

    private func applyBackground(_ shape: NotchGeometry.Shape, _ fill: NotchBackground.Fill) {
        self.shape = shape
        self.fill = fill
        glassHost?.removeFromSuperview()
        glassHost = nil
        glass = nil
        guard fill == .glass else { return }
        let background: NSView
        if #available(macOS 26, *) {
            background = NSGlassEffectView()
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            background = effect
        }
        let host = NSView()
        host.wantsLayer = true
        host.layer?.mask = glassMask
        background.autoresizingMask = [.width, .height]
        host.addSubview(background)
        addSubview(host, positioned: .below, relativeTo: nil)
        glassHost = host
        glass = background
    }

    /// The content's opacity: it fades in as the island is drawn down and out as it is pulled up.
    /// The items that show only while the island is open fade with it, so they appear and go with the sheet.
    func fadeContent(to alpha: CGFloat, animated: Bool) {
        contentAlpha = alpha
        let fading = [container] + (leftEntries + rightEntries).filter(\.revealed).compactMap { itemViews[$0.core.slot] }
        for view in fading {
            if animated { view.animator().alphaValue = alpha } else { view.alphaValue = alpha }
        }
    }

    func setContent(_ view: NSView?) {
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        // Sized in `layout`: the container may still be empty here.
        container.addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if let glassHost, let glass {
            glassHost.frame = bounds
            glass.frame = glassHost.bounds
            // The host is not flipped, so the outline is turned over to match.
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glassMask.frame = glassHost.bounds
            glassMask.path = outline().copy(using: &flip)
            CATransaction.commit()
        }
        let inset = NotchGeometry.contentInset
        // The content fills the panel under the strip, whose row is the tabs, level with the notch. It
        // keeps its final size while the panel is still growing, which only shows as much of it as fits.
        let size = contentSize == .zero ? bounds.size : contentSize
        container.frame = NSRect(
            x: inset, y: header, width: max(size.width - 2 * inset, 0), height: max(size.height - header - inset, 0)
        )
        container.isHidden = !open
        container.subviews.first?.frame = container.bounds
        overlay.frame = bounds

        let left = leftEntries.map(\.core)
        let right = rightEntries.map(\.core)
        let leftWidth = NotchGeometry.earWidth(left)
        let rightWidth = NotchGeometry.earWidth(right)
        let leftEnd: CGFloat
        let rightStart: CGFloat
        if shape == .notch {
            leftEnd = notch.lowerBound - NotchGeometry.notchClearance
            rightStart = notch.upperBound + NotchGeometry.notchClearance
        } else {
            // One row centred on the screen's middle.
            let total = NotchGeometry.capsuleRowWidth(left: leftWidth, right: rightWidth)
            leftEnd = notch.lowerBound - total / 2 + leftWidth
            rightStart = leftEnd + (leftWidth > 0 && rightWidth > 0 ? NotchGeometry.capsuleGap : 0)
        }
        place(leftEntries, from: leftEnd - leftWidth)
        place(rightEntries, from: rightStart)
    }

    /// Each item of an ear in its place, level with the notch. The System tab's capsule reaches past
    /// its bars into the gap beside them.
    private func place(_ entries: [IslandEntry], from start: CGFloat) {
        let side = NotchGeometry.featureIconSide(scale: scale)
        let offsets = NotchGeometry.earOffsets(entries.map(\.core))
        for (entry, offset) in zip(entries, offsets) {
            guard let view = itemViews[entry.core.slot] else { continue }
            let reach = entry.core.isBars ? NotchGeometry.highlightPadding : 0
            let height = entry.readouts.map { max(side, $0.size.height * scale) } ?? side
            view.frame = NSRect(
                x: start + offset - reach, y: (header - height) / 2, width: entry.core.width + 2 * reach, height: height
            )
        }
    }

    private var showsBody: Bool { open || picker != nil }

    /// The island's outline now: the closed strip, or the strip with the panel below it.
    private func outline() -> CGPath {
        let key = OutlineKey(size: bounds.size, shape: shape, showsBody: showsBody, strip: strip, header: header)
        if let cachedOutline, cachedOutline.key == key { return cachedOutline.path }
        let path = showsBody
            ? IslandOutline.popup(size: bounds.size, shape: shape, strip: strip, header: header, bottomCorner: Self.openCorner)
            : IslandOutline.closed(size: bounds.size, shape: shape, corner: Self.closedCorner)
        cachedOutline = (key, path)
        return path
    }

    /// The notch's black, carried on as the panel that hangs from the strip, in one outline with it. The
    /// strip's top sits above the view, so the island meets the screen edge square, as the notch does.
    /// Away from the notch the black is a capsule of its own, with the panel growing under it.
    override func draw(_ dirtyRect: NSRect) {
        guard fill == .black, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(outline())
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        // The window's shadow follows what is drawn, which changes as the panel grows.
        window?.invalidateShadow()
    }

    /// Where the outline is not, in the corners beside the strip, the island is not there to point at.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard showsBody, let superview else { return super.hitTest(point) }
        return outline().contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    /// What the pointer is on while the island is closed: the tab of the item under it, whichever ear
    /// it is in, or the System page with the panel of a status glyph. Anywhere else, none. Open, the
    /// island is already on a tab.
    func targetUnderPointer() -> PanelTarget? {
        guard let window, !open else { return nil }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let entries = leftEntries + rightEntries
        let hit = entries.first { itemViews[$0.core.slot].map { !$0.isHidden && $0.frame.contains(point) } ?? false }
        switch hit?.core.slot {
        case .item(let item): return PanelTarget(section: item.section)
        case .status(let status): return PanelTarget(section: .system, panel: status.panel)
        case nil: return nil
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    /// One area that follows the view as it grows and shrinks, so it is made once.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }

    override func mouseDown(with event: NSEvent) {
        // The items take their own clicks, open or closed.
        if !open { onClick() }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick(self, NSPoint(x: (notch.lowerBound + notch.upperBound) / 2, y: header + 4))
    }

    // MARK: Dropping

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops, !open, ShelfPasteboard.containsFileURLs(sender.draggingPasteboard) else { return [] }
        if picker == nil {
            guard opensOnDrag else { return [] }
            onDragEntered()
        }
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hovered = nil
        onDragExited()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hovered = nil
        onDragEnded()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateHover(sender)
        guard let target = hovered else { return false }
        let urls = ShelfPasteboard.fileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        hovered = nil
        return onDrop(urls, target)
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return hovered == nil ? [] : .copy
    }

    private func updateHover(_ sender: NSDraggingInfo) {
        let next = picker?.target(at: convert(sender.draggingLocation, from: nil))
        if next != hovered { hovered = next }
    }
}

/// Over everything else, so a glass capsule does not hide it. It draws the stash tiles while files are
/// dragged, and the outline that marks the island as a place to drop them; it takes no events itself.
private final class PickerOverlay: NSView {
    var hovered: ShelfPickerLayout.Target? { didSet { needsDisplay = true } }
    private var layout: ShelfPickerLayout?
    private var stashes: [ShelfStash] = []
    private var hint = false
    private var corner: CGFloat = 0
    private var isNotch = true

    override var isFlipped: Bool { true }

    func configure(layout: ShelfPickerLayout?, stashes: [ShelfStash], hint: Bool, corner: CGFloat, isNotch: Bool) {
        self.layout = layout
        self.stashes = stashes
        self.hint = hint
        self.corner = corner
        self.isNotch = isNotch
        setAccessibilityElement(layout != nil)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Choose a stash for the dragged files"))
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let layout { return ShelfPickerTiles.draw(layout, stashes: stashes, hovered: hovered) }
        guard hint else { return }
        // Its top corners sit above the view, so the outline meets the screen edge square, as the notch does.
        let top: CGFloat = isNotch ? corner : 0
        let outline = NSBezierPath(
            continuousRoundedRect: NSRect(x: 1, y: -top + 1, width: bounds.width - 2, height: bounds.height + top - 2),
            radius: corner
        )
        outline.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        outline.stroke()
    }
}

extension NSBezierPath {
    /// A rounded rectangle with Apple's continuous corners, whose curve eases into the straight edges
    /// instead of meeting them at a circle's tangent.
    convenience init(continuousRoundedRect rect: NSRect, radius: CGFloat) {
        self.init(cgPath: RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
    }
}
