import AppKit
import Quartz
import QuickLookThumbnailing
import SysbarCore

/// One shelf on screen: its panel and the files it holds.
@MainActor
private final class Shelf {
    let panel = ShelfPanel()
    var files: [URL] = []
    /// An empty shelf opened from the menu stays until it is closed or filled.
    var keepOpen = false
}

/// Floating shelves, summoned by shaking a file drag, holding a key, the notch, a shortcut or the
/// menu bar icon. Any number can be open. A shelf remembers where its files are (nothing is
/// copied) until they are dragged out again. Off until Settings turns it on.
/// Mouse events need no Accessibility permission; key events would.
@MainActor
final class ShelfController {
    private let preferences: Preferences
    /// Set by the owner once it can open Settings on the shelf's page.
    var openSettings: () -> Void = {}
    private var tray: ShelfTray?
    private let notch = ShelfNotch()
    private lazy var hotKeys = ShelfHotKeys { [weak self] id in
        guard let self else { return }
        if id == ShelfHotKeys.newShelf { newShelf() } else { newShelfFromClipboard() }
    }
    /// The open shelves, the one used last at the end.
    private var shelves: [Shelf] = []
    private var monitors: [Any] = []
    private var lastChangeCount = 0
    /// The current drag put file URLs on the pasteboard.
    private var fileDrag = false
    /// The drag started in an app Settings says to ignore.
    private var ignoredSource = false
    /// This drag already shook hard enough to summon a shelf.
    private var summoned = false
    /// Recent pointer samples for the shake, in seconds since launch.
    private var shakeSamples: [(time: TimeInterval, sample: DragShake.Sample)] = []
    /// True while a shelf itself is being moved or is dragging files out.
    private var interacting = false

    var openShelfCount: Int { shelves.count }

    init(preferences: Preferences) {
        self.preferences = preferences
        notch.onDrop = { [weak self] urls in self?.addFiles(urls) }
    }

    func sync() {
        if preferences.shelfEnabled {
            start()
        } else if !monitors.isEmpty || !shelves.isEmpty {
            stop()
        }
        var shortcuts: [UInt32: KeyShortcut] = [:]
        if preferences.shelfEnabled {
            shortcuts[ShelfHotKeys.newShelf] = preferences.shelfShortcuts["new"]
            shortcuts[ShelfHotKeys.newShelfFromClipboard] = preferences.shelfShortcuts["clipboard"]
        }
        hotKeys.apply(shortcuts.compactMapValues { $0 })
        let wantsTray = preferences.shelfEnabled && preferences.showsShelfIcon
        if wantsTray, tray == nil {
            tray = ShelfTray(controller: self)
        } else if !wantsTray, let tray {
            tray.remove()
            self.tray = nil
        }
    }

    func appWillTerminate() {
        stop()
    }

    private func start() {
        guard monitors.isEmpty else { return }
        lastChangeCount = NSPasteboard(name: .drag).changeCount
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
        }) { monitors.append(monitor) }
        // A global monitor does not see events delivered to this app, such as moving a shelf.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event) }
            return event
        }) { monitors.append(monitor) }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        // Emptied before the history changes: that change calls back into `sync`.
        let held = shelves
        shelves = []
        held.forEach { $0.panel.orderOut(nil) }
        notch.remove()
        interacting = false
        fileDrag = false
        summoned = false
        shakeSamples = []
        held.forEach { archive($0.files) }
    }

    private func observe(_ event: NSEvent) {
        if interacting {
            // A drag that never begins must not leave the shelves deaf to the next shake.
            if event.type == .leftMouseUp { interacting = false }
            return
        }
        switch event.type {
        case .leftMouseDown:
            summoned = false
            fileDrag = false
            shakeSamples = []
            ignoredSource = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                .map(preferences.shelfIgnoredApps.contains) ?? false
            notePasteboard()
        case .leftMouseDragged:
            notePasteboard()
            guard fileDrag, !summoned else { return }
            if preferences.shelfModifierEnabled, event.modifierFlags.contains(preferences.shelfModifier.flag) {
                return summon()
            }
            guard preferences.shelfShake else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let point = NSEvent.mouseLocation
            shakeSamples.append((now, DragShake.Sample(x: point.x, y: point.y)))
            shakeSamples.removeAll { now - $0.time > 0.8 }
            let sensitivity = preferences.shelfSensitivity
            if DragShake.reversals(shakeSamples.map(\.sample), minTravel: sensitivity.minTravel) >= sensitivity.reversalsNeeded {
                summon()
            }
        case .leftMouseUp:
            notch.dragEnded()
            fileDrag = false
            summoned = false
            shakeSamples = []
            // The drag ended somewhere else: a shelf summoned for it that is still empty has nothing
            // to offer. A drop on a shelf and this mouse-up can arrive in either order, hence the wait.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !interacting else { return }
                for shelf in shelves where shelf.files.isEmpty && !shelf.keepOpen { close(shelf) }
            }
        default:
            break
        }
    }

    private func notePasteboard() {
        let pasteboard = NSPasteboard(name: .drag)
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Types only: reading the file URLs here can stall the app that started the drag.
        // shortcut: file URLs only, not promised files from Photos or Safari.
        fileDrag = !ignoredSource && ShelfPasteboard.containsFileURLs(pasteboard)
        if fileDrag, preferences.shelfNotchEnabled { notch.dragBegan(style: preferences.shelfNotchStyle) }
    }

    /// A new shelf beside the pointer, once per drag. Drop on it, or on a shelf that is already open.
    private func summon() {
        summoned = true
        show(makeShelf(), nearCursor: true)
    }

    private func makeShelf() -> Shelf {
        let shelf = Shelf()
        let view = shelf.panel.shelfView
        view.onDrop = { [weak self, weak shelf] urls in
            if let self, let shelf { accept(urls, to: shelf) }
        }
        view.onRemove = { [weak self, weak shelf] urls in
            if let self, let shelf { remove(urls, from: shelf) }
        }
        view.onClear = { [weak self, weak shelf] in
            if let self, let shelf { clearShelf(shelf) }
        }
        view.onInteractionBegan = { [weak self] in self?.interacting = true }
        view.onInteractionEnded = { [weak self] in self?.interacting = false }
        shelf.panel.dockedNeighbours = { [weak self, weak shelf] in
            self?.shelves.filter { $0 !== shelf && $0.panel.dockEdge != nil }.map { $0.panel.frame } ?? []
        }
        view.onExportEnded = { [weak self, weak shelf] urls, dropped in
            guard let self else { return }
            interacting = false
            lastChangeCount = NSPasteboard(name: .drag).changeCount
            if dropped, let shelf { remove(urls, from: shelf) }
        }
        shelves.append(shelf)
        return shelf
    }

    /// Shows a shelf. A hidden one appears beside the pointer after a shake, otherwise in the
    /// default corner from Settings, beside any shelves already there.
    private func show(_ shelf: Shelf, nearCursor: Bool) {
        let panel = shelf.panel
        let hidden = !panel.isVisible
        refresh(shelf)
        if hidden {
            let cursor = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let others = shelves.filter { $0 !== shelf && $0.panel.isVisible }.map { $0.panel.frame }
                panel.move(to: nearCursor
                    ? ShelfFiles.origin(size: panel.frame.size, near: cursor, visible: visible)
                    : ShelfFiles.origin(size: panel.frame.size, placement: preferences.shelfPlacement, visible: visible, avoiding: others))
            }
        }
        panel.present()
    }

    /// Marks a shelf as the one used last.
    private func touch(_ shelf: Shelf) {
        shelves.removeAll { $0 === shelf }
        shelves.append(shelf)
    }

    private func accept(_ urls: [URL], to shelf: Shelf) {
        shelf.files += ShelfFiles.worthShelving(urls, alreadyHeld: shelf.files)
        touch(shelf)
        refresh(shelf)
    }

    private func remove(_ urls: [URL], from shelf: Shelf) {
        shelf.files.removeAll(where: urls.contains)
        refresh(shelf)
        if shelf.files.isEmpty { close(shelf) }
    }

    private func clearShelf(_ shelf: Shelf) {
        archive(shelf.files)
        close(shelf)
    }

    private func close(_ shelf: Shelf) {
        shelf.keepOpen = false
        shelves.removeAll { $0 === shelf }
        shelf.panel.dismiss()
    }

    /// Puts a shelf's files in the menu's recent list.
    private func archive(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        preferences.shelfHistory = ShelfHistory.adding(
            ShelfRecord(paths: urls.map(\.path), date: Date()), to: preferences.shelfHistory
        )
    }

    /// Forgets files that were moved or deleted elsewhere, then redraws.
    private func refresh(_ shelf: Shelf) {
        shelf.files.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        shelf.panel.update(files: shelf.files)
    }

    // MARK: Menu

    var history: [ShelfRecord] { preferences.shelfHistory }
    var clipboardHasFiles: Bool { ShelfPasteboard.containsFileURLs(.general) }
    var shortcutForNewShelf: KeyShortcut? { preferences.shelfShortcuts["new"] }
    var shortcutForClipboard: KeyShortcut? { preferences.shelfShortcuts["clipboard"] }

    func openShelfSettings() { openSettings() }

    func clearHistory() { preferences.shelfHistory = [] }

    /// An empty shelf beside the others. One that is already empty is brought forward instead.
    func newShelf() {
        let shelf = shelves.first { $0.files.isEmpty } ?? makeShelf()
        shelf.keepOpen = true
        touch(shelf)
        // One that was folded into a tab is the one being asked for.
        shelf.panel.undock()
        show(shelf, nearCursor: false)
    }

    func newShelfFromClipboard() {
        addFiles(ShelfPasteboard.fileURLs(on: .general))
    }

    /// Files that arrive without a drag onto a shelf: from the clipboard, or dropped on the notch.
    private func addFiles(_ incoming: [URL]) {
        let target = preferences.shelfAddBehavior == .currentShelf ? shelves.last : nil
        let urls = ShelfFiles.worthShelving(incoming, alreadyHeld: target?.files ?? [])
        guard !urls.isEmpty else { return NSSound.beep() }
        let shelf = target ?? makeShelf()
        shelf.files += urls
        shelf.keepOpen = false
        touch(shelf)
        show(shelf, nearCursor: false)
    }

    /// A recent shelf comes back as a new one beside the others.
    func restore(_ record: ShelfRecord) {
        let urls = record.paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return NSSound.beep() }
        preferences.shelfHistory.removeAll { $0 == record }
        let shelf = makeShelf()
        shelf.files = urls
        show(shelf, nearCursor: false)
    }

    /// Every open shelf goes to the recent list.
    func closeAllShelves() {
        for shelf in shelves {
            archive(shelf.files)
            close(shelf)
        }
    }
}

/// File URLs on a pasteboard, including the older filenames list Finder still writes.
enum ShelfPasteboard {
    static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func containsFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(filenames)
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        guard containsFileURLs(pasteboard) else { return [] }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }
        let names = pasteboard.propertyList(forType: filenames) as? [String] ?? []
        return names.map { URL(fileURLWithPath: $0) }
    }
}

@MainActor
private final class ShelfPanel: NSPanel {
    let shelfView = ShelfView()
    private var dismissing = false
    /// The edge this shelf is docked to, as a tab; nil while it is an ordinary shelf.
    private(set) var dockEdge: ShelfDockEdge?
    /// Frames of the other docked shelves, so tabs on one edge do not sit on each other.
    var dockedNeighbours: () -> [NSRect] = { [] }

    init() {
        let size = shelfView.fittedSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // A floating panel hides whenever the app is inactive, which is almost always here.
        isFloatingPanel = false
        hidesOnDeactivate = false
        // Above document windows, including while this menu-bar app is not active.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        shelfView.frame = NSRect(origin: .zero, size: size)
        shelfView.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
            glass.cornerRadius = ShelfView.corner
            glass.contentView = shelfView
            contentView = glass
        } else {
            contentView = shelfView
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A docked tab reaches past the screen edge, which AppKit would otherwise pull back.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        dockEdge == nil ? super.constrainFrameRect(frameRect, to: screen) : frameRect
    }

    func update(files: [URL]) {
        shelfView.files = files
    }

    /// Fades in, or just comes to the front when already shown.
    func present() {
        dismissing = false
        if !isVisible { alphaValue = 0 }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible, !dismissing else { return }
        dismissing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            animator().alphaValue = 0
        }, completionHandler: {
            // Holds the panel until the fade ends, even if its shelf is already gone.
            MainActor.assumeIsolated {
                // Shown again while fading out: stay.
                guard self.dismissing else { return }
                self.dismissing = false
                self.orderOut(nil)
            }
        })
    }

    /// Resizes to the content, keeping the top-left corner where it is and the shelf on its screen.
    func fit() {
        guard dockEdge == nil else { return }
        var next = frame
        next.size = shelfView.fittedSize
        next.origin.y = frame.maxY - next.height
        next = clamped(next, to: ownScreen)
        guard next != frame else { return }
        guard isVisible, !dismissing else { return setFrame(next, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(next, display: true)
        }
    }

    /// Moves the shelf by a drag, keeping it on the screen under the pointer.
    func move(to origin: NSPoint) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? ownScreen
        setFrame(clamped(NSRect(origin: origin, size: frame.size), to: screen), display: true)
    }

    /// After a drag of the shelf: one left against the left or right edge folds into a tab there.
    func dockIfAtEdge() {
        guard dockEdge == nil, let screen = ownScreen,
              let edge = ShelfFiles.dockEdge(of: frame, in: screen.visibleFrame),
              !hasNeighbour(on: edge, of: screen) else { return }
        let visible = screen.visibleFrame
        dockEdge = edge
        shelfView.dockEdge = edge
        animate(to: ShelfFiles.dockFrame(edge: edge, in: visible, midY: frame.midY, avoiding: dockedNeighbours()))
    }

    /// A tab reaches past its edge, so on an edge shared with another display it would show up there.
    private func hasNeighbour(on edge: ShelfDockEdge, of screen: NSScreen) -> Bool {
        NSScreen.screens.contains { other in
            guard other !== screen else { return false }
            let touching = edge == .left
                ? abs(other.frame.maxX - screen.frame.minX) < 2
                : abs(other.frame.minX - screen.frame.maxX) < 2
            return touching && other.frame.minY < screen.frame.maxY && other.frame.maxY > screen.frame.minY
        }
    }

    /// A click on the tab: the shelf opens beside its edge, at the height of the tab.
    func undock() {
        guard let edge = dockEdge, let visible = ownScreen?.visibleFrame else { return }
        dockEdge = nil
        shelfView.dockEdge = nil
        let size = shelfView.fittedSize
        animate(to: NSRect(origin: ShelfFiles.undockedOrigin(edge: edge, size: size, in: visible, midY: frame.midY), size: size))
    }

    private func animate(to rect: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(rect, display: true)
        }
    }

    /// Tints the glass while files hover over the shelf.
    func setTargeted(_ targeted: Bool) {
        if #available(macOS 26, *), let glass = contentView as? NSGlassEffectView {
            glass.tintColor = targeted ? NSColor.controlAccentColor.withAlphaComponent(0.25) : nil
        }
    }

    /// The screen most of the shelf is on. A resize must not carry it to the screen the pointer is on.
    private var ownScreen: NSScreen? {
        func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        return NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) } ?? NSScreen.main
    }

    private func clamped(_ rect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return rect }
        var rect = rect
        rect.origin.x = min(max(rect.minX, visible.minX), max(visible.minX, visible.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, visible.minY), max(visible.minY, visible.maxY - rect.height))
        return rect
    }
}

/// Quick Look asks from outside the main actor. The shelf sets `urls` before the panel opens.
private final class ShelfPreviewSource: NSObject, QLPreviewPanelDataSource {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}

/// The whole shelf. Collapsed, the files sit in one pile: drag it to take them all, click it to
/// see each file as a list or a gallery. Drops land here, including those on the pile or a file.
@MainActor
private final class ShelfView: NSView, NSDraggingSource {
    static let corner: CGFloat = 22
    private static let pileSize = NSSize(width: 176, height: 196)
    private static let wideWidth: CGFloat = 288
    private static let header: CGFloat = 44
    private static let inset: CGFloat = 8
    private static let rowHeight: CGFloat = 44
    private static let columns = 3
    private static let gap: CGFloat = 4
    private static var cellWidth: CGFloat { (wideWidth - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns) }
    private static let cellHeight: CGFloat = 100
    private static let cardSide: CGFloat = 96

    var onDrop: ([URL]) -> Void = { _ in }
    var onRemove: ([URL]) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onInteractionBegan: () -> Void = {}
    var onInteractionEnded: () -> Void = {}
    var onExportEnded: ([URL], Bool) -> Void = { _, _ in }

    /// Everything but the tab, hidden while the shelf is docked.
    private let body = FlippedView()
    private let drawer = ShelfGrabView()
    private let drawerChevron = NSImageView()
    private let drawerCount = NSTextField(labelWithString: "")
    private let empty = ShelfEmptyView()
    private let pile = ShelfGrabView()
    /// One picture per file in the pile, so a new file slides in on top instead of redrawing the rest.
    private var cards: [URL: CALayer] = [:]
    private let pileLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let backButton = ShelfButton()
    private let styleButton = ShelfButton()
    private let clearButton = ShelfButton()
    private let actionsButton = ShelfButton()
    private let scroll = NSScrollView()
    private let list = FlippedView()
    /// The list or gallery items, kept per file so adding one does not rebuild the others.
    private var items: [URL: ShelfGrabView] = [:]
    private var thumbnails: [String: NSImage] = [:]
    private var expanded = false
    private var gallery = true
    private var exporting: [URL] = []
    /// The files the menu, Quick Look and Share apply to, and the view the menu came from.
    private var menuFiles: [URL] = []
    private weak var menuAnchor: NSView?
    private var sharePicker: NSSharingServicePicker?
    private let previewSource = ShelfPreviewSource()
    private var targeted = false { didSet { if targeted != oldValue { applyChrome() } } }
    /// What the drag in progress was answered with on entering; updates repeat it instead of re-reading the files.
    private var dragOperation: NSDragOperation = []

    /// Set by the panel when it docks or opens: the shelf shows as a tab, or as itself.
    var dockEdge: ShelfDockEdge? {
        didSet { if dockEdge != oldValue { applyDock() } }
    }

    var files: [URL] = [] {
        didSet {
            guard files != oldValue else { return }
            if files.isEmpty { expanded = false }
            rebuild(animated: true)
        }
    }

    var fittedSize: NSSize {
        guard expanded else { return Self.pileSize }
        let body: CGFloat
        if gallery {
            let rows = CGFloat((files.count + Self.columns - 1) / Self.columns)
            body = min(rows, 3) * Self.cellHeight
        } else {
            body = CGFloat(min(files.count, 6)) * Self.rowHeight
        }
        return NSSize(width: Self.wideWidth, height: Self.header + body + Self.inset)
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.pileSize))
        wantsLayer = true
        layer?.cornerRadius = Self.corner
        if #unavailable(macOS 26) {
            let background = NSVisualEffectView(frame: bounds)
            background.material = .popover
            background.blendingMode = .behindWindow
            background.state = .active
            background.autoresizingMask = [.width, .height]
            background.wantsLayer = true
            background.layer?.cornerRadius = Self.corner
            background.layer?.masksToBounds = true
            addSubview(background)
        }
        body.frame = bounds
        body.autoresizingMask = [.width, .height]
        addSubview(body)
        body.addSubview(empty)

        // Layer-hosting, so the cards animate on their own.
        pile.layer = CALayer()
        pile.wantsLayer = true
        pile.dropTarget = self
        pile.toolTip = L("Click to see the files, drag to take them all")
        pile.onClick = { [weak self] in self?.setExpanded(true) }
        pile.onDragOut = { [weak self] view, event in
            guard let self else { return }
            beginExport(files, from: view, event: event)
        }
        pile.makeMenu = { [weak self] in self?.menu(for: self?.files ?? [], from: self?.pile, single: false) }
        body.addSubview(pile)
        for label in [pileLabel, titleLabel] {
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            body.addSubview(label)
        }

        configure(backButton, "chevron.left", L("Back"), #selector(backPicked))
        configure(styleButton, "list.bullet", L("Show as list"), #selector(stylePicked))
        configure(clearButton, "xmark", L("Clear shelf"), #selector(clearPicked))
        configure(actionsButton, "ellipsis", L("Actions"), #selector(actionsPicked))

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        body.addSubview(scroll)

        drawer.isHidden = true
        drawer.dropTarget = self
        drawer.toolTip = L("Click to see the files, drag to take them all")
        drawer.onClick = { [weak self] in (self?.window as? ShelfPanel)?.undock() }
        drawer.onDragOut = { [weak self] view, event in
            guard let self else { return }
            beginExport(files, from: view, event: event)
        }
        drawer.makeMenu = { [weak self] in self?.menu(for: self?.files ?? [], from: self?.drawer, single: false) }
        drawerChevron.imageScaling = .scaleProportionallyDown
        drawerChevron.contentTintColor = .secondaryLabelColor
        drawerCount.font = .systemFont(ofSize: 11, weight: .semibold)
        drawerCount.textColor = .secondaryLabelColor
        drawerCount.alignment = .center
        drawer.addSubview(drawerChevron)
        drawer.addSubview(drawerCount)
        addSubview(drawer)

        registerForDraggedTypes([.fileURL, ShelfPasteboard.filenames])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("File shelf"))
        rebuild(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func configure(_ button: ShelfButton, _ symbol: String, _ label: String, _ action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.imagePosition = .imageOnly
        if #available(macOS 26, *) {
            button.bezelStyle = .glass
            button.borderShape = .circle
            button.controlSize = .small
        } else {
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
        }
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = action
        body.addSubview(button)
    }

    override func layout() {
        super.layout()
        drawer.frame = bounds
        // The tab is the 30 points at the screen edge; the rest of the panel is past it.
        let tab = NSRect(
            x: dockEdge == .left ? ShelfFiles.dockOverhang : 0, y: 0, width: ShelfFiles.dockSize.width, height: bounds.height
        )
        drawerChevron.frame = NSRect(x: tab.minX, y: bounds.midY - 14, width: tab.width, height: 28)
        drawerCount.frame = NSRect(x: tab.minX, y: bounds.midY + 18, width: tab.width, height: 14)
        empty.frame = bounds.insetBy(dx: 12, dy: 12)
        let side: CGFloat = 28
        let right = NSRect(x: bounds.width - side - 10, y: 10, width: side, height: side)
        actionsButton.frame = right
        clearButton.frame = NSRect(x: 10, y: 10, width: side, height: side)
        backButton.frame = clearButton.frame
        styleButton.frame = right.offsetBy(dx: -side - 6, dy: 0)
        titleLabel.frame = NSRect(x: 44, y: 15, width: bounds.width - 44 - (bounds.width - styleButton.frame.minX) - 4, height: 18)
        pile.frame = NSRect(x: (bounds.width - 128) / 2, y: 34, width: 128, height: 124)
        pileLabel.frame = NSRect(x: 10, y: pile.frame.maxY + 6, width: bounds.width - 20, height: 18)
        scroll.frame = NSRect(x: 0, y: Self.header, width: bounds.width, height: bounds.height - Self.header - Self.inset)
        let ordered = files.compactMap { items[$0] }
        let height = gallery
            ? CGFloat((ordered.count + Self.columns - 1) / Self.columns) * Self.cellHeight
            : CGFloat(ordered.count) * Self.rowHeight
        list.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: height)
        for (index, item) in ordered.enumerated() {
            item.setFrameOrigin(gallery
                ? NSPoint(
                    x: Self.inset + CGFloat(index % Self.columns) * (Self.cellWidth + Self.gap),
                    y: CGFloat(index / Self.columns) * Self.cellHeight
                )
                : NSPoint(x: Self.inset, y: CGFloat(index) * Self.rowHeight))
        }
    }

    private func rebuild(animated: Bool) {
        let holding = !files.isEmpty
        let showsPile = holding && !expanded
        empty.isHidden = holding
        for view in [pile, pileLabel] as [NSView] { reveal(view, showsPile, animated: animated) }
        // An empty shelf can be closed too.
        reveal(clearButton, !expanded, animated: animated)
        for view in [backButton, styleButton, titleLabel, scroll] as [NSView] { reveal(view, expanded, animated: animated) }
        reveal(actionsButton, holding, animated: animated)
        let count = files.count == 1 ? L("1 file") : L("%@ files", "\(files.count)")
        pileLabel.stringValue = count
        titleLabel.stringValue = count
        pile.setAccessibilityLabel(count)
        drawer.setAccessibilityLabel(count)
        drawerCount.stringValue = holding ? "\(files.count)" : ""

        let label = gallery ? L("Show as list") : L("Show as gallery")
        styleButton.image = NSImage(systemSymbolName: gallery ? "list.bullet" : "square.grid.3x2", accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        styleButton.toolTip = label
        styleButton.setAccessibilityLabel(label)

        updateCards(animated: animated)
        updateItems(animated: animated)
        thumbnails = thumbnails.filter { key, _ in files.contains { key.hasSuffix($0.path) } }
        needsLayout = true
        (window as? ShelfPanel)?.fit()
    }

    private func applyDock() {
        let docked = dockEdge != nil
        if let dockEdge {
            drawerChevron.image = NSImage(
                systemSymbolName: dockEdge == .left ? "chevron.right" : "chevron.left", accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))
        }
        reveal(drawer, docked, animated: true)
        if docked {
            body.isHidden = true
        } else {
            body.alphaValue = 0
            body.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                body.animator().alphaValue = 1
            }
        }
        needsLayout = true
    }

    /// Shows or hides a view, fading it in when it appears.
    private func reveal(_ view: NSView, _ shown: Bool, animated: Bool) {
        guard view.isHidden == shown else { return }
        view.isHidden = !shown
        guard shown, animated else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            view.animator().alphaValue = 1
        }
    }

    // MARK: The pile

    /// The newest three files, newest on top. A new file drops in; the rest slide down a step.
    private func updateCards(animated: Bool) {
        let shown = Array(files.suffix(3))
        for (url, card) in cards where !shown.contains(url) {
            cards[url] = nil
            card.opacity = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { card.removeFromSuperlayer() }
        }
        for url in shown where cards[url] == nil {
            let card = CALayer()
            card.contentsGravity = .resizeAspect
            card.contentsScale = window?.backingScaleFactor ?? 2
            card.shadowOpacity = 0.25
            card.shadowRadius = 4
            card.shadowOffset = CGSize(width: 0, height: -1)
            card.contents = NSWorkspace.shared.icon(forFile: url.path)
            thumbnail(of: url, side: Self.cardSide) { card.contents = $0 }
            cards[url] = card
            pile.layer?.addSublayer(card)
            if animated {
                card.add(Self.arrival(), forKey: "arrive")
            }
        }
        placeCards(animated: animated)
    }

    private func placeCards(animated: Bool) {
        let bounds = CGRect(x: 0, y: 0, width: 128, height: 124)  // the pile's fixed size, set in layout
        let shown = Array(files.suffix(3))
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let turns: [CGFloat] = [0, 0.12, -0.12]
        for (order, url) in shown.enumerated() {
            guard let card = cards[url] else { continue }
            let depth = shown.count - 1 - order
            card.zPosition = CGFloat(order)
            card.bounds = CGRect(x: 0, y: 0, width: Self.cardSide, height: Self.cardSide)
            card.position = CGPoint(x: bounds.midX + CGFloat(depth) * 5, y: bounds.midY - CGFloat(depth) * 3)
            let lift: CGFloat = targeted && !expanded ? 1.08 : 1
            card.transform = CATransform3DScale(CATransform3DMakeRotation(turns[depth], 0, 0, 1), lift, lift, 1)
            card.opacity = 1
        }
        CATransaction.commit()
    }

    private static func arrival() -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.25
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = 0.3
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return group
    }

    // MARK: List and gallery

    private func updateItems(animated: Bool) {
        let wanted = expanded ? Set(files) : []
        for (url, item) in items where !wanted.contains(url) {
            item.removeFromSuperview()
            items[url] = nil
        }
        for url in files where wanted.contains(url) && items[url] == nil {
            let item = gallery ? makeCell(url) : makeRow(url)
            items[url] = item
            list.addSubview(item)
            if animated {
                item.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    item.animator().alphaValue = 1
                }
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value, !files.isEmpty || !value else { return }
        expanded = value
        rebuild(animated: true)
    }

    @objc private func backPicked() { setExpanded(false) }

    @objc private func stylePicked() {
        gallery.toggle()
        items.values.forEach { $0.removeFromSuperview() }
        items = [:]
        rebuild(animated: true)
    }

    /// A file in the list: icon, name, then kind and size.
    private func makeRow(_ url: URL) -> ShelfGrabView {
        let row = makeItem(url, size: NSSize(width: Self.wideWidth - Self.inset * 2, height: Self.rowHeight))
        let icon = NSImageView(frame: NSRect(x: 6, y: 6, width: 32, height: 32))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        thumbnail(of: url, side: 32) { [weak icon] in icon?.image = $0 }

        let values = try? url.resourceValues(forKeys: [.localizedNameKey, .localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey])
        let width = row.bounds.width - 54
        let name = label(values?.localizedName ?? url.lastPathComponent, size: 13, frame: NSRect(x: 46, y: 5, width: width, height: 17))
        var facts = [values?.localizedTypeDescription].compactMap { $0 }
        if values?.isDirectory != true, let bytes = values?.fileSize {
            facts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        let detail = label(facts.joined(separator: " · "), size: 11, frame: NSRect(x: 46, y: 23, width: width, height: 15))
        detail.textColor = .secondaryLabelColor
        [icon, name, detail].forEach(row.addSubview)
        row.setAccessibilityLabel([name.stringValue, detail.stringValue].joined(separator: ", "))
        return row
    }

    /// A file in the gallery: a thumbnail with its name under it.
    private func makeCell(_ url: URL) -> ShelfGrabView {
        let cell = makeItem(url, size: NSSize(width: Self.cellWidth, height: Self.cellHeight - Self.gap))
        let picture = NSImageView(frame: NSRect(x: 8, y: 6, width: cell.bounds.width - 16, height: 64))
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.image = NSWorkspace.shared.icon(forFile: url.path)
        thumbnail(of: url, side: 64) { [weak picture] in picture?.image = $0 }
        let title = FileManager.default.displayName(atPath: url.path)
        let name = label(title, size: 11, frame: NSRect(x: 4, y: 74, width: cell.bounds.width - 8, height: 15))
        name.alignment = .center
        [picture, name].forEach(cell.addSubview)
        cell.setAccessibilityLabel(title)
        return cell
    }

    private func makeItem(_ url: URL, size: NSSize) -> ShelfGrabView {
        // Sized before its contents go in, so nothing inside is stretched by autoresizing.
        let item = ShelfGrabView(frame: NSRect(origin: .zero, size: size))
        item.highlightsOnHover = true
        item.dropTarget = self
        item.toolTip = url.path
        item.onDragOut = { [weak self] view, event in self?.beginExport([url], from: view, event: event) }
        item.onOpen = { NSWorkspace.shared.open(url) }
        item.makeMenu = { [weak self, weak item] in self?.menu(for: [url], from: item, single: true) }
        return item
    }

    private func label(_ text: String, size: CGFloat, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = frame
        return label
    }

    /// A Quick Look thumbnail, from the cache when the shelf has drawn this file before.
    private func thumbnail(of url: URL, side: CGFloat, apply: @escaping (NSImage) -> Void) {
        let key = "\(Int(side)) \(url.path)"
        if let cached = thumbnails[key] { return apply(cached) }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: window?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                self?.thumbnails[key] = image
                apply(image)
            }
        }
    }

    // MARK: Moving the shelf

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // Labels are part of the shelf's body, which moves it.
        return hit is NSTextField ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window as? ShelfPanel else { return }
        onInteractionBegan()
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        var moved = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking
        ) { event, stop in
            guard let event, event.type == .leftMouseDragged else { stop.pointee = true; return }
            let mouse = NSEvent.mouseLocation
            moved = true
            window.move(to: NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
        onInteractionEnded()
        // A plain click on a shelf that rests at an edge must not fold it away.
        if moved { window.dockIfAtEdge() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    private func applyChrome() {
        layer?.borderWidth = targeted ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        empty.targeted = targeted
        (window as? ShelfPanel)?.setTargeted(targeted)
        placeCards(animated: true)
    }

    // MARK: Dropping in

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation = operation(for: sender)
        targeted = dragOperation == .copy
        return dragOperation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        let urls = newFiles(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }

    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource as AnyObject === self { return [] }
        return newFiles(in: sender).isEmpty ? [] : .copy
    }

    private func newFiles(in sender: NSDraggingInfo) -> [URL] {
        ShelfFiles.worthShelving(ShelfPasteboard.fileURLs(on: sender.draggingPasteboard), alreadyHeld: files)
    }

    // MARK: Dragging out

    private func beginExport(_ urls: [URL], from view: NSView, event: NSEvent) {
        guard !urls.isEmpty else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(
                NSRect(x: point.x - 16 + offset, y: point.y - 16 - offset, width: 32, height: 32),
                contents: NSWorkspace.shared.icon(forFile: url.path)
            )
            return item
        }
        exporting = urls
        onInteractionBegan()
        view.beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Like a drag from Finder: the destination picks move or copy. Another shelf may take it too;
        // a shelf refuses its own files, so a drop back where it started does nothing.
        [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let urls = exporting
        exporting = []
        onExportEnded(urls, !operation.isEmpty)
    }

    // MARK: Actions

    @objc private func actionsPicked() {
        let menu = menu(for: files, from: actionsButton, single: false)
        // Right edge under the button, which sits in the corner; x: 0 would open it at the panel's left edge.
        let x = actionsButton.frame.maxX - menu.size.width
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: actionsButton.frame.maxY + 4), in: self)
    }

    /// Actions for one file, or for every file on the shelf.
    private func menu(for urls: [URL], from anchor: NSView?, single: Bool) -> NSMenu {
        menuFiles = urls
        menuAnchor = anchor
        let menu = NSMenu()
        menu.addItem(actionItem(L("Open"), #selector(openPicked)))
        if urls.count == 1 {
            let openWith = NSMenuItem(title: L("Open With"), action: nil, keyEquivalent: "")
            openWith.submenu = openWithMenu(urls[0])
            menu.addItem(openWith)
        }
        menu.addItem(actionItem(L("Quick Look"), #selector(quickLookPicked)))
        menu.addItem(actionItem(L("Show in Finder"), #selector(revealPicked)))
        menu.addItem(actionItem(L("Share"), #selector(sharePicked)))
        menu.addItem(.separator())
        if single { menu.addItem(actionItem(L("Remove from shelf"), #selector(removePicked))) }
        menu.addItem(actionItem(L("Clear shelf"), #selector(clearPicked)))
        return menu
    }

    private func openWithMenu(_ file: URL) -> NSMenu {
        let menu = NSMenu()
        for app in NSWorkspace.shared.urlsForApplications(toOpen: file).prefix(8) {
            let item = actionItem(FileManager.default.displayName(atPath: app.path), #selector(openWithPicked(_:)))
            item.representedObject = app
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func clearPicked() { onClear() }

    @objc private func openPicked() {
        menuFiles.forEach { NSWorkspace.shared.open($0) }
    }

    @objc private func openWithPicked(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(menuFiles, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func revealPicked() {
        NSWorkspace.shared.activateFileViewerSelecting(menuFiles)
    }

    @objc private func removePicked() { onRemove(menuFiles) }

    @objc private func sharePicked() {
        guard !menuFiles.isEmpty else { return }
        let anchor: NSView = menuAnchor ?? self
        let picker = NSSharingServicePicker(items: menuFiles)
        sharePicker = picker
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    @objc private func quickLookPicked() {
        guard !menuFiles.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        previewSource.urls = menuFiles
        window?.makeKey()
        window?.makeFirstResponder(self)
        panel.updateController()
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { !menuFiles.isEmpty }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewSource.urls = menuFiles
        panel.dataSource = previewSource
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
}

/// Something on the shelf that can be dragged out: a file, or the pile that holds them all.
/// A click runs `onClick`, a double-click opens, a drag hands the files to whatever is under the pointer.
/// Files dropped on it go to `dropTarget`, the shelf.
@MainActor
private final class ShelfGrabView: NSView {
    var onDragOut: (NSView, NSEvent) -> Void = { _, _ in }
    var onOpen: (() -> Void)?
    var onClick: (() -> Void)?
    var makeMenu: () -> NSMenu? = { nil }
    var highlightsOnHover = false
    weak var dropTarget: NSView? {
        didSet { registerForDraggedTypes([.fileURL, ShelfPasteboard.filenames]) }
    }
    private var hovered = false { didSet { needsDisplay = true } }
    /// When this view was last pressed, so a double-click is two presses here, not one here after one elsewhere.
    private var lastPress: TimeInterval = -.infinity

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Its labels and pictures are part of it.
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        // Clicking the pile expands it, so the second click of a quick double-click lands on a file; it must not open it.
        let isDoubleClick = event.clickCount == 2 && event.timestamp - lastPress < 1
        lastPress = event.timestamp
        if isDoubleClick { onOpen?(); return }
        let start = NSEvent.mouseLocation
        var dragEvent: NSEvent?
        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking
        ) { event, stop in
            guard let event, event.type == .leftMouseDragged else { stop.pointee = true; return }
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - start.x, mouse.y - start.y) > 4 {
                dragEvent = event
                stop.pointee = true
            }
        }
        if let dragEvent { onDragOut(self, dragEvent) } else { onClick?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.draggingEntered(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropTarget?.draggingUpdated(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropTarget?.draggingExited(sender) }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropTarget?.draggingEnded(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropTarget?.performDragOperation(sender) ?? false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard highlightsOnHover else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard hovered else { return }
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool {
        guard let action = onClick ?? onOpen else { return false }
        action()
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = makeMenu() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
        return true
    }
}

/// The dashed drop zone an empty shelf shows.
@MainActor
private final class ShelfEmptyView: NSView {
    var targeted = false { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = targeted ? .controlAccentColor : .tertiaryLabelColor
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        border.lineWidth = 1.5
        border.setLineDash([6, 4], count: 2, phase: 0)
        color.setStroke()
        border.stroke()

        let symbol = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .regular).applying(.init(paletteColors: [color])))
        let text = NSAttributedString(string: L("Drop files here"), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: targeted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ])
        let textSize = text.size()
        let symbolSize = symbol?.size ?? .zero
        let top = bounds.midY - (symbolSize.height + 8 + textSize.height) / 2
        symbol?.draw(in: NSRect(
            x: bounds.midX - symbolSize.width / 2, y: top + textSize.height + 8,
            width: symbolSize.width, height: symbolSize.height
        ))
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: top))
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class ShelfButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
