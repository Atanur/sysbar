import AppKit
import SysbarCore

extension NSScreen {
    /// The display's id, which stays the same while it is connected.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// The islands at the top of the displays Sysbar is shown on: one `NotchController` for each, which
/// follows the displays being connected, removed, moved and made the active one. The panel is one
/// at a time, so opening one island closes the others.
@MainActor
final class NotchDisplays {
    /// How often the display with the active menu bar is looked at while it is the choice: focus moving
    /// to a window on another display raises no notification.
    private static let activePollSeconds: TimeInterval = 1
    /// How often full screen is looked for while the island shows otherwise: a game or player that
    /// covers a display without a Space of its own raises no notification of its own.
    private static let fullScreenPollSeconds: TimeInterval = 1

    /// Builds the panel's content each time an island opens, given that island's top row and the tab asked for.
    var makeContent: (NotchRowModel, PanelTarget?) -> NSViewController = { _, _ in NSViewController() }
    var onClose: () -> Void = {}
    var onMenu: (NSView, NSPoint) -> Void = { _, _ in }
    var stashes: () -> [ShelfStash] = { [] }
    var onDrop: ([URL], ShelfPickerLayout.Target) -> Void = { _, _ in }
    /// The features that are on, and which tab the open panel is on, for every island.
    let features = NotchFeatureModel()

    private var islands: [CGDirectDisplayID: NotchController] = [:]
    private var running = false
    private var choice = NotchDisplayChoice.builtIn
    private var look = NotchLook()
    private var opensOnHover = true
    private var visibility = NotchIslandVisibility.always
    /// The displays showing something full screen, where the island hides until the pointer reaches it.
    private var fullScreen: Set<CGDirectDisplayID> = []
    private var drops = (enabled: false, opensOnDrag: false)
    private var left: NSImage?
    private var ears = NotchEarLayout.standard
    private var description = ""
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var activePoll: Timer?
    private var fullScreenPoll: Timer?
    /// Watch the pointer, which brings a concealed island back; they live while any island is concealed.
    private var pointerMonitors: [Any] = []

    var isRunning: Bool { running }
    var isOpen: Bool { islands.values.contains { $0.isOpen } }
    var isPinned: Bool { islands.values.contains { $0.isPinned } }

    func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
        observe(workspace, NSWorkspace.didActivateApplicationNotification)
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification)
        reconcile()
    }

    func stop() {
        guard running else { return }
        running = false
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        activePoll?.invalidate()
        activePoll = nil
        fullScreenPoll?.invalidate()
        fullScreenPoll = nil
        stopWatchingPointer()
        fullScreen = []
        islands.values.forEach { $0.stop() }
        islands = [:]
    }

    /// Which displays show an island, and how every island looks and opens.
    func configure(choice: NotchDisplayChoice, look: NotchLook, opensOnHover: Bool, visibility: NotchIslandVisibility) {
        let displaysChanged = choice != self.choice
        self.choice = choice
        self.look = look
        self.opensOnHover = opensOnHover
        self.visibility = visibility
        islands.values.forEach(apply)
        if displaysChanged, running { reconcile() }
        updateActivePoll()
        updateFullScreen()
    }

    /// The readouts' bars, the features that are on, what the ears hold, and the text VoiceOver reads.
    func update(left: NSImage?, features: [NotchFeature], statuses: [NotchStatusInfo], ears: NotchEarLayout, description: String) {
        self.left = left
        self.ears = ears
        self.description = description
        if self.features.features != features { self.features.features = features }
        if self.features.statuses != statuses { self.features.statuses = statuses }
        islands.values.forEach { $0.update(left: left, ears: ears, description: description) }
    }

    /// Whether files may be dropped on the islands, and whether a drag over one opens the picker.
    func setDrops(enabled: Bool, opensOnDrag: Bool) {
        drops = (enabled, opensOnDrag)
        islands.values.forEach { $0.setDrops(enabled: enabled, opensOnDrag: opensOnDrag) }
    }

    // MARK: Stash picker

    /// Opens the stash picker on the display the pointer is on, or else the first that shows an island.
    func showPicker(summoned: Bool) {
        target()?.showPicker(summoned: summoned)
    }

    /// The marker that tells the islands are places to drop files, while they are dragged.
    func setDragHint(_ shown: Bool) {
        islands.values.forEach { $0.setDragHint(shown) }
    }

    func dragEnded() {
        islands.values.forEach { $0.dragEnded() }
    }

    // MARK: Opening and closing

    /// Opens the island that is open, or else the one on the pointer's display, kept open.
    func open(pinned: Bool) {
        (islands.values.first { $0.isOpen } ?? target())?.open(pinned: pinned)
    }

    func close() {
        islands.values.forEach { $0.close() }
    }

    /// The open panel's content wants another height: the island that is open follows it.
    func contentSizeChanged() {
        islands.values.forEach { $0.contentSizeChanged() }
    }


    // MARK: Displays

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        observers.append((center, token))
    }

    /// The displays that should have an island now.
    private func wantedDisplays() -> [CGDirectDisplayID] {
        let screens = NSScreen.screens.compactMap { screen in
            screen.displayID.map { NotchDisplay(id: $0, isBuiltIn: CGDisplayIsBuiltin($0) != 0) }
        }
        return choice.select(from: screens, primary: NSScreen.screens.first?.displayID, active: NSScreen.main?.displayID)
    }

    /// Gives every wanted display an island and takes the others' away, then measures them again.
    /// An island that is open stays where it is until it closes: the active display moving off it
    /// would otherwise pull the panel away from under the pointer.
    private func reconcile() {
        guard running else { return }
        updateFullScreen()
        let wanted = Set(wantedDisplays())
        for (id, island) in islands where !wanted.contains(id) && !(island.isOpen && onScreen(id)) {
            island.stop()
            islands[id] = nil
        }
        for id in wanted where islands[id] == nil {
            islands[id] = makeIsland(id)
        }
        islands.values.forEach { $0.screensChanged() }
        updateActivePoll()
    }

    private func onScreen(_ id: CGDirectDisplayID) -> Bool {
        NSScreen.screens.contains { $0.displayID == id }
    }

    private func makeIsland(_ id: CGDirectDisplayID) -> NotchController {
        let island = NotchController(displayID: id, features: features)
        island.makeContent = { [weak self] row, section in self?.makeContent(row, section) ?? NSViewController() }
        island.onWillOpen = { [weak self, weak island] in
            self?.islands.values.filter { $0 !== island }.forEach { $0.close() }
        }
        island.onClose = { [weak self] in
            self?.onClose()
            // An island kept open past its display's turn goes now.
            self?.reconcile()
        }
        island.onMenu = { [weak self] view, point in self?.onMenu(view, point) }
        island.stashes = { [weak self] in self?.stashes() ?? [] }
        island.onDrop = { [weak self] urls, target in self?.onDrop(urls, target) }
        apply(island)
        island.start()
        island.setDrops(enabled: drops.enabled, opensOnDrag: drops.opensOnDrag)
        island.update(left: left, ears: ears, description: description)
        return island
    }

    private func apply(_ island: NotchController) {
        island.look = look
        island.opensOnHover = opensOnHover
        island.concealed = visibility.isConcealed(fullScreen: fullScreen.contains(island.displayID))
    }

    // MARK: Full screen

    /// Looks at which displays are full screen now, hides the islands there until the pointer reaches
    /// them, and keeps the watch on the pointer and the poll for full screen running as long as they are needed.
    private func updateFullScreen() {
        guard running else { return }
        let now = visibility == .always ? FullScreenProbe.displays() : []
        if now != fullScreen {
            fullScreen = now
            islands.values.forEach(apply)
        }
        if islands.values.contains(where: \.concealed) { watchPointer() } else { stopWatchingPointer() }
        if visibility == .always, fullScreenPoll == nil {
            fullScreenPoll = Timer.scheduledTimer(withTimeInterval: Self.fullScreenPollSeconds, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullScreen() }
            }
        } else if visibility != .always {
            fullScreenPoll?.invalidate()
            fullScreenPoll = nil
        }
    }

    /// Mouse monitors need no permission. Dragged events are included, so files dragged to the top of the
    /// screen bring the island back to be dropped on.
    private func watchPointer() {
        guard pointerMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { pointerMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { pointerMonitors.append(monitor) }
    }

    private func stopWatchingPointer() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        islands.values.forEach { $0.pointerMoved(to: point) }
    }

    /// The island on the display the pointer is on; failing that, the first one, the primary display's.
    private func target() -> NotchController? {
        let pointer = NSEvent.mouseLocation
        let under = NSScreen.screens.first { $0.frame.contains(pointer) }?.displayID
        if let under, let island = islands[under] { return island }
        let primary = NSScreen.screens.first?.displayID
        return primary.flatMap { islands[$0] } ?? islands.values.first
    }

    /// While the active display is the choice, looks for it moving, as nothing says when it does.
    private func updateActivePoll() {
        guard running, choice == .active else {
            activePoll?.invalidate()
            activePoll = nil
            return
        }
        guard activePoll == nil else { return }
        activePoll = Timer.scheduledTimer(withTimeInterval: Self.activePollSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.reconcile()
            }
        }
    }
}
