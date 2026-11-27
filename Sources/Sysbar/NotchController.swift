import AppKit
import SysbarCore

/// Sysbar at the top of one display instead of in the menu bar; `NotchDisplays` runs one per display
/// that shows it. Around the notch it is an island with the readouts in its left ear and an icon for
/// each feature in its right; on a display without a notch it is a small capsule at the top centre
/// with the same two. It is black or glass as the settings say. Resting the
/// pointer on it (or clicking it, if the settings say so) opens the same panel the menu bar item
/// opens, below it, as a panel that hangs from the strip's bottom edge; moving away closes it again. A click keeps it open until a click elsewhere or Escape, like the popover. A feature's
/// icon opens the panel on its tab. While files are dragged, the island opens into the stash picker
/// instead, and files dropped on a tile go to that stash. The pointer is followed with a tracking
/// area on the island itself, which needs no permission.
@MainActor
final class NotchController {
    private static let openDelay: TimeInterval = 0.15
    private static let closeDelay: TimeInterval = 0.35
    /// A concealed island that was revealed hides again this long after the pointer has left it.
    private static let concealDelay: TimeInterval = 0.5
    private static let fadeSeconds: TimeInterval = 0.15
    /// The panel under the strip is drawn down like a sheet, slower at the end; the strip never moves.
    /// The sheet's motion. Closing plays opening backwards: as long, on the same curve reversed in time.
    private static let sheetSeconds: TimeInterval = 0.3
    private static let openCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    private static let closeCurve = CAMediaTimingFunction(controlPoints: 0.8, 0, 0.8, 0.2)

    /// Builds the panel's content each time it opens, given this island's top row and the tab (and
    /// the panel on the System page) asked for, if any; it is released when the panel closes.
    var makeContent: (NotchRowModel, PanelTarget?) -> NSViewController = { _, _ in NSViewController() }
    /// About to open: the other displays' islands close, as the panel is one at a time.
    var onWillOpen: () -> Void = {}
    var onClose: () -> Void = {}
    /// A right click on the island: the small Settings, About and Quit menu.
    var onMenu: (NSView, NSPoint) -> Void = { _, _ in }
    /// The stashes the picker offers, read each time it opens.
    var stashes: () -> [ShelfStash] = { [] }
    /// Files dropped on a tile of the picker.
    var onDrop: ([URL], ShelfPickerLayout.Target) -> Void = { _, _ in }
    /// The display this island is on.
    let displayID: CGDirectDisplayID
    /// The features that are on, and which tab the open panel is on; shared by every island.
    let features: NotchFeatureModel
    /// The strip's icon size, which the open panel's settings button shares.
    let row = NotchRowModel()
    /// What fills the island and how its icons look.
    var look = NotchLook() { didSet { if look != oldValue { layout(animated: false) } } }
    /// Resting the pointer on the island opens it; without, only a click does.
    var opensOnHover = true
    /// The island is hidden until the pointer reaches it: in full screen, or when it is set to show only
    /// then. Hidden, it draws nothing and takes no clicks; `pointerMoved` brings it back.
    var concealed = false { didSet { if concealed != oldValue { concealmentChanged() } } }

    private var panel: IslandPanel?
    private var content: NSViewController?
    /// The content of a panel that is closing, which stays in view while the island is pulled up.
    private var retiring: NSViewController?
    /// The island's size when it was last open, which closing starts from.
    private var openSize: NSSize = .zero
    /// Bumped by each opening or closing, so one that was overtaken does not finish.
    private var motionToken = 0
    /// An opening or closing is under way, which the readouts' updates do not interrupt.
    private var moving = false
    /// The click and key monitors that live while the panel is open.
    private var clickMonitors: [Any] = []
    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    /// Opened by a click, or clicked since: hovering away no longer closes it.
    private var pinned = false
    /// The readouts' bars, for the System item, and what the user put in each ear.
    private var left: NSImage?
    private var ears = NotchEarLayout.standard
    /// The stash picker is showing: files are being dragged.
    private var offersStashes = false
    /// Summoned by a shake or a key, so it stays until the drag ends, wherever the pointer goes.
    private var pickerSummoned = false
    private var dragHint = false
    /// A newer drag cancels the pending hide of the last one.
    private var hideToken = 0
    /// Concealed but shown for now, as the pointer is on it or was a moment ago.
    private var revealed = false
    /// Whether the panel is drawn and takes events, as `updateVisibility` last set it.
    private var showing = true
    /// A menu of the island is up, which keeps it shown.
    private var menuUp = false
    private var pendingConceal: DispatchWorkItem?
    /// Where the pointer reveals it: the closed island with some slack, up to the screen's top edge.
    private var revealZone: CGRect = .zero

    init(displayID: CGDirectDisplayID, features: NotchFeatureModel) {
        self.displayID = displayID
        self.features = features
    }

    var isRunning: Bool { panel != nil }
    var isOpen: Bool { content != nil }
    /// Open and kept open: opened by a click, or clicked since.
    var isPinned: Bool { content != nil && pinned }

    func start() {
        guard panel == nil else { return }
        let panel = IslandPanel(features: features)
        let island = panel.island
        row.onContentHeight = { [weak self] in self?.contentSizeChanged() }
        island.onEnter = { [weak self] in self?.pointerEntered() }
        island.onExit = { [weak self] in self?.pointerExited() }
        island.onClick = { [weak self] in self?.open(pinned: true) }
        island.onRightClick = { [weak self] view, point in
            guard let self else { return }
            menuUp = true
            onMenu(view, point)
            menuUp = false
            updateVisibility()
        }
        island.onDragEntered = { [weak self] in self?.showPicker(summoned: false) }
        island.onDragExited = { [weak self] in
            guard let self, !pickerSummoned else { return }
            hidePicker()
        }
        island.onDragEnded = { [weak self] in self?.dragEnded() }
        island.onDrop = { [weak self] urls, target in
            guard let self else { return false }
            hidePicker()
            onDrop(urls, target)
            return true
        }
        panel.onCancel = { [weak self] in self?.close() }
        self.panel = panel
        layout(animated: false)
        panel.orderFrontRegardless()
        updateVisibility(animated: false)
    }

    /// A display was connected, removed, moved or changed its resolution: the island is measured again.
    func screensChanged() {
        layout(animated: false)
    }

    func stop() {
        pendingConceal?.cancel()
        close()
        motionToken += 1
        moving = false
        retiring = nil
        panel?.island.setContent(nil)
        panel?.orderOut(nil)
        panel = nil
    }

    /// The readouts' bars, what the ears hold, and the text VoiceOver reads.
    func update(left: NSImage?, ears: NotchEarLayout, description: String) {
        self.left = left
        self.ears = ears
        panel?.island.describe(description)
        layout(animated: false)
    }

    /// Whether files may be dropped on the island, and whether a drag over it opens the picker.
    func setDrops(enabled: Bool, opensOnDrag: Bool) {
        panel?.island.acceptsDrops = enabled
        panel?.island.opensOnDrag = enabled && opensOnDrag
        if !enabled { hidePicker() }
    }

    // MARK: Stash picker

    /// Opens the island into the stash picker. `summoned` ones, from a shake or a key, stay until the
    /// drag ends; one opened by dragging over the island closes when the pointer leaves it.
    func showPicker(summoned: Bool) {
        guard panel != nil, content == nil else { return }
        hideToken += 1
        pendingOpen?.cancel()
        pendingClose?.cancel()
        offersStashes = true
        pickerSummoned = summoned
        layout(animated: false)
    }

    func hidePicker() {
        hideToken += 1
        guard offersStashes else { return }
        offersStashes = false
        pickerSummoned = false
        layout(animated: true)
        updateVisibility()
    }

    /// The marker that tells the island is a place to drop files, while they are dragged.
    func setDragHint(_ shown: Bool) {
        guard dragHint != shown else { return }
        dragHint = shown
        layout(animated: false)
    }

    /// The drag is over. The picker goes a moment later: the drop and the mouse-up can arrive in either order.
    func dragEnded() {
        setDragHint(false)
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.hideToken else { return }
                self.hidePicker()
            }
        }
    }

    // MARK: Concealing

    /// Open, showing the picker or with a menu up: the island stays, wherever the pointer goes.
    private var held: Bool { content != nil || retiring != nil || offersStashes || menuUp }

    /// The pointer moved (or dragged files) to `point`, in screen coordinates: onto a concealed island's
    /// reveal zone shows it; off it, it hides again a moment later.
    func pointerMoved(to point: NSPoint) {
        guard concealed else { return }
        if revealZone.contains(point) {
            pendingConceal?.cancel()
            guard !revealed else { return }
            revealed = true
            updateVisibility()
            // Resting on it still opens it, though the pointer was there before it appeared.
            if panel?.frame.contains(point) == true { pointerEntered() }
        } else {
            updateVisibility()
        }
    }

    private func concealmentChanged() {
        pendingConceal?.cancel()
        revealed = false
        updateVisibility()
    }

    /// Fades the island in or out as it should now be, and arms the hiding of one that was revealed.
    private func updateVisibility(animated: Bool = true) {
        guard let panel else { return }
        let shown = !concealed || revealed || held
        if concealed, revealed, !held, !revealZone.contains(NSEvent.mouseLocation), pendingConceal == nil || pendingConceal?.isCancelled == true {
            schedule(&pendingConceal, after: Self.concealDelay) { [weak self] in
                guard let self else { return }
                pendingConceal = nil
                if held || revealZone.contains(NSEvent.mouseLocation) { return updateVisibility() }
                revealed = false
                updateVisibility()
            }
        }
        guard shown != showing || !animated else { return }
        showing = shown
        panel.ignoresMouseEvents = !shown
        let still = !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !still else { return panel.alphaValue = shown ? 1 : 0 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeSeconds
            panel.animator().alphaValue = shown ? 1 : 0
        }
    }

    // MARK: Opening and closing

    func toggle() {
        isOpen ? close() : open(pinned: true)
    }

    func open(pinned: Bool) {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        guard let panel else { return }
        if content == nil {
            onWillOpen()
            offersStashes = false
            pickerSummoned = false
            retiring = nil
            // The icon size is known before the panel is built, which then has its final height at once.
            if let geometry = measure() { updateRow(geometry) }
            // Opened from the readouts or an icon, by resting the pointer there or a click: that tab.
            let content = makeContent(row, panel.island.targetUnderPointer())
            self.content = content
            panel.island.setContent(content.view)
            // Laid out now, so the island opens at its final size instead of correcting it a moment later.
            content.view.layoutSubtreeIfNeeded()
            // The content changes size, as when a panel unfolds or another page is shown; the island follows.
            layout(animated: true)
            watchClicks()
        }
        if pinned { pin() }
    }

    func close() {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        guard content != nil else { return hidePicker() }
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        pinned = false
        panel?.becomesKeyOnlyIfNeeded = true
        // The next panel measures itself afresh; until it has, its first size is the hosting controller's.
        row.forgetHeight()
        // The content stays until the island has been pulled up.
        retiring = content
        content = nil
        layout(animated: true)
        onClose()
    }

    /// The content changed height, as when another page is shown or a panel unfolds: the island follows,
    /// drawn down or pulled up like the sheet that opens it. The content is already laid out at its final
    /// size, so it does not move while the island grows or shrinks.
    func contentSizeChanged() {
        guard let content else { return }
        content.view.layoutSubtreeIfNeeded()
        layout(animated: true)
    }

    private func pin() {
        pinned = true
        pendingClose?.cancel()
        // Keys such as Escape reach it, without bringing Sysbar forward. A click in it makes it key too,
        // which a panel that only becomes key when it needs a text field would not.
        panel?.becomesKeyOnlyIfNeeded = false
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    private func pointerEntered() {
        pendingClose?.cancel()
        guard opensOnHover, content == nil, !offersStashes else { return }
        schedule(&pendingOpen, after: Self.openDelay) { [weak self] in self?.open(pinned: false) }
    }

    private func pointerExited() {
        pendingOpen?.cancel()
        guard content != nil, !pinned else { return }
        schedule(&pendingClose, after: Self.closeDelay) { [weak self] in
            guard let self, !pinned else { return }
            close()
        }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        slot?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        slot = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// A click in the island keeps it open; a click anywhere else closes it: in another app, on the
    /// desktop or menu bar, in another Sysbar window or island, with any mouse button. Escape closes it
    /// too. Whatever the panel itself presents, such as a Picker's menu, a context menu or a popover,
    /// is part of it.
    private func watchClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window === self.panel {
                    self.pin()
                } else if !self.belongsToPanel(event.window) {
                    self.close()
                }
            }
            return event
        }) { clickMonitors.append(monitor) }
        // The panel is not what AppKit sends Escape to when a SwiftUI view holds the focus, so it is
        // taken here. A text field being edited, or an input method composing, keeps it.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }) { clickMonitors.append(monitor) }
    }

    /// Escape in the panel closes it, unless a field is using it.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, let panel, event.window === panel else { return false }
        if let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor || editor.hasMarkedText() { return false }
        close()
        return true
    }

    /// A menu or popover the panel opened: a window above it, or one of its children.
    private func belongsToPanel(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        if window.parent === panel || window.level.rawValue > panel.level.rawValue { return true }
        let name = String(describing: type(of: window))
        return name.contains("Menu") || name.contains("Popover")
    }

    // MARK: Layout

    /// This island's display, measured now; nil once it has been disconnected.
    private func measure() -> NotchGeometry? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        return NotchGeometry.make(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea
        )
    }

    /// How much the readouts and icons are scaled on this display: the chosen size, within its row.
    private func scale(_ geometry: NotchGeometry) -> CGFloat {
        NotchGeometry.contentScale(look.iconSize, rowHeight: geometry.collapsedFrame(left: 0, right: 0).height)
    }

    /// What is in one ear while the island is closed or open, at this display's scale: the items the
    /// layout shows in that state that are on, the System item as the readouts' bars (or, open and with
    /// no bars, as an icon, so the System tab is still there), and as many as fit the ear. The closed
    /// island's right ear starts with the status glyphs that apply.
    private func entries(on ear: NotchEar, open: Bool, scale: CGFloat) -> [IslandEntry] {
        let available = Set(features.features.map(\.item)).union([.system])
        let shown = ears.ears(available: available, open: open)
        let side = NotchGeometry.featureIconSide(scale: scale)
        let all: [IslandEntry] = (ear == .left ? shown.left : shown.right).compactMap { item in
            let reveal = ears.visibility(of: item) == .whenOpen
            guard item == .system else { return IslandEntry(core: NotchEarEntry(item: item, width: side), revealed: reveal) }
            if let left {
                return IslandEntry(
                    core: NotchEarEntry(item: item, width: left.size.width * scale, isBars: true), readouts: left, revealed: reveal
                )
            }
            return open ? IslandEntry(core: NotchEarEntry(item: item, width: side), revealed: true) : nil
        }
        let glyphs: [IslandEntry] = open || ear != .right ? [] : features.statuses.map {
            IslandEntry(core: NotchEarEntry(slot: .status($0.status), width: side))
        }
        let fitted = NotchGeometry.fit((glyphs + all).map(\.core), ear: ear)
        return (glyphs + all).filter { fitted.contains($0.core) }
    }

    private func width(of entries: [IslandEntry]) -> CGFloat { NotchGeometry.earWidth(entries.map(\.core)) }

    /// The closed island, or with `open` the row the open one keeps on top, which has the items
    /// that show only while it is open as well.
    private func collapsedFrame(_ geometry: NotchGeometry, open: Bool = false) -> CGRect {
        let size = scale(geometry)
        return geometry.collapsedFrame(
            left: width(of: entries(on: .left, open: open, scale: size)),
            right: width(of: entries(on: .right, open: open, scale: size))
        )
    }

    /// Tells the open panel how big the icons are.
    private func updateRow(_ geometry: NotchGeometry) {
        let side = NotchGeometry.featureIconSide(scale: scale(geometry))
        if row.iconSide != side { row.iconSide = side }
    }

    private func layout(animated: Bool) {
        guard let panel, let geometry = measure() else { return }
        // Readouts refreshing mid-motion would cut it short; it settles by itself when it ends.
        guard !moving || animated else { return }
        let collapsed = collapsedFrame(geometry)
        revealZone = IslandRevealZone.rect(strip: collapsed, screenTop: geometry.screen.maxY)
        updateRow(geometry)
        // A panel that is closing still looks open, and is where it was when it began.
        let closing = content == nil && retiring != nil
        let showsOpen = content != nil || closing
        let itemScale = scale(geometry)
        let leftEntries = entries(on: .left, open: showsOpen, scale: itemScale)
        let rightEntries = entries(on: .right, open: showsOpen, scale: itemScale)
        // The strip: the closed row, or the open one with the items that show only then.
        let strip = collapsedFrame(geometry, open: showsOpen)
        var frame = collapsed
        var picker: ShelfPickerLayout?
        var stashes: [ShelfStash] = []
        if let content {
            var size = content.preferredContentSize
            if size.width <= 0 || size.height <= 0 { size = content.view.fittingSize }
            // What the panel last measured itself at wins: it follows changes within a page too.
            if row.contentHeight > 0 { size.height = row.contentHeight }
            // The strip on top, the content's panel below it, wide enough for the open row's ears.
            frame = geometry.expandedFrame(content: size, collapsed: collapsedFrame(geometry, open: true))
            openSize = frame.size
        } else if offersStashes {
            stashes = self.stashes()
            let tiles = ShelfPickerLayout(
                stashes: stashes.map(\.id), top: collapsed.height, minWidth: geometry.minimumOpenWidth(collapsed)
            )
            picker = tiles
            frame = geometry.pickerFrame(size: tiles.size, collapsed: collapsed)
        }
        let shown = closing ? panel.frame : frame
        panel.island.configure(
            geometry: geometry, header: collapsed.height,
            notch: (geometry.anchor.minX - shown.minX)...(geometry.anchor.maxX - shown.minX),
            strip: (strip.minX - shown.minX)...(strip.maxX - shown.minX),
            left: leftEntries, right: rightEntries, open: showsOpen,
            contentSize: closing ? openSize : (content != nil ? frame.size : .zero),
            picker: picker, stashes: stashes, dragHint: dragHint, look: look, scale: itemScale
        )
        // A shadow sets the open black panel off the page below; closed, it is part of the menu bar. Glass
        // gets none: the window's shadow follows a square outline there and shows as a black rim.
        panel.hasShadow = (content != nil || closing || picker != nil) && panel.island.drawsBlack
        // The tiles are found by position, so the picker opens at its size at once.
        let animates = animated && picker == nil && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if closing { return retract(to: frame, animated: animates) }
        guard frame != panel.frame else { return }
        guard animates else {
            motionToken += 1
            moving = false
            panel.island.fadeContent(to: 1, animated: false)
            return panel.setFrame(frame, display: true)
        }
        draw(down: frame, from: collapsed)
    }

    /// Opens the panel like a sheet drawn down from under the strip: the window is as wide as the panel
    /// at once, still as tall as the strip, which shows nothing more, and then the panel grows downward,
    /// its content fading in.
    private func draw(down frame: CGRect, from collapsed: CGRect) {
        guard let panel else { return }
        var start = panel.frame
        let fresh = start.height <= collapsed.height + 0.5
        if frame.width != start.width, frame.height >= start.height {
            start = CGRect(x: frame.minX, y: frame.maxY - start.height, width: frame.width, height: start.height)
            panel.setFrame(start, display: true)
        }
        if fresh { panel.island.fadeContent(to: 0, animated: false) }
        move(panel, to: frame, seconds: Self.sheetSeconds, curve: Self.openCurve, changes: {
            panel.island.fadeContent(to: 1, animated: true)
        })
    }

    /// Closes the island by pulling the sheet up into the strip, then narrows the window to the strip at
    /// once: opening's steps in reverse.
    private func retract(to collapsed: CGRect, animated: Bool) {
        guard let panel else { return }
        let up = CGRect(x: panel.frame.minX, y: collapsed.maxY - collapsed.height, width: panel.frame.width, height: collapsed.height)
        guard animated, up != panel.frame else { return finishClosing(in: panel) }
        move(panel, to: up, seconds: Self.sheetSeconds, curve: Self.closeCurve, changes: {
            panel.island.fadeContent(to: 0, animated: true)
        }, then: { [weak self] in self?.finishClosing(in: panel) })
    }

    private func finishClosing(in panel: IslandPanel) {
        motionToken += 1
        moving = false
        retiring = nil
        panel.island.setContent(nil)
        panel.island.fadeContent(to: 1, animated: false)
        layout(animated: false)
    }

    /// Animates the panel's frame, with `changes` alongside it, and runs `then` unless something else has started since.
    private func move(
        _ panel: IslandPanel, to frame: CGRect, seconds: TimeInterval, curve: CAMediaTimingFunction,
        changes: @escaping () -> Void, then: (() -> Void)? = nil
    ) {
        motionToken += 1
        let token = motionToken
        moving = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = seconds
            context.timingFunction = curve
            panel.animator().setFrame(frame, display: true)
            changes()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.motionToken else { return }
                self.moving = false
                if let then { then() } else { self.layout(animated: false) }
            }
        })
    }
}

/// Sits over the menu bar and the notch, on every Space and over full-screen apps.
@MainActor
private final class IslandPanel: NSPanel {
    let island: IslandView
    var onCancel: () -> Void = {}

    init(features: NotchFeatureModel) {
        island = IslandView(features: features)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Before the level: setting it resets the level to normal, below the menu bar, which then takes every click.
        isFloatingPanel = false
        // Above the menu bar's own window, so the pointer reaches the island.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        contentView = island
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// AppKit would push it below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}
