import AppKit
import OSLog
import SysbarCore

/// Which stash the Stash tab shows, which one is being renamed, and which one waits for its deletion
/// to be confirmed.
@MainActor
final class StashTabState: ObservableObject {
    @Published var selectedID = ShelfStash.mainID
    @Published var renamingID: ShelfStash.ID?
    @Published var deletingID: ShelfStash.ID?
}

/// The stash: named, persistent collections of files and copied text, shown on the Stash tab. Files
/// are kept by bookmark, so nothing is copied and a moved or renamed file is still found. Dragging
/// files asks the owner to offer the stashes (a shake, or a modifier key held, summons them; a drag
/// over the island needs no help from here) and puts dropped files in the one chosen. Off until
/// Settings turns it on.
/// Mouse events need no Accessibility permission; key events would.
@MainActor
final class ShelfController: ObservableObject {
    private static let log = Logger(subsystem: "com.atanur.sysbar", category: "stash")

    /// Where a file item is now.
    enum FileState: Equatable {
        case found(URL)
        case missing
    }

    private let preferences: Preferences
    private var store: ShelfStashStore
    @Published private(set) var library: ShelfLibrary
    /// What the Stash tab shows and edits. It has its own object, so choosing a stash redraws the tab
    /// and not every view that watches the stashes.
    let tab = StashTabState()
    /// The stash the Stash tab shows.
    var selectedID: ShelfStash.ID {
        get { tab.selectedID }
        set { tab.selectedID = newValue }
    }
    /// The stash whose name is being edited on the tab.
    var renamingID: ShelfStash.ID? {
        get { tab.renamingID }
        set { tab.renamingID = newValue }
    }
    /// The stash waiting for the user to confirm its deletion.
    var deletingID: ShelfStash.ID? {
        get { tab.deletingID }
        set { tab.deletingID = newValue }
    }
    /// Where each file item is, found when the stashes load, when the tab opens and when files are added.
    @Published private(set) var fileStates: [UUID: FileState] = [:]
    /// Set by the owner: brings up the Stash tab, for a stash that was just made and wants a name.
    var onReveal: () -> Void = {}
    /// Set by the owner: a file drag began or ended, for the marker on the island.
    var onFileDragBegan: () -> Void = {}
    var onFileDragEnded: () -> Void = {}
    /// Set by the owner: a shake or the modifier key asks for the stashes while files are dragged.
    var onSummon: () -> Void = {}

    /// The stash that last took something, which the clipboard shortcut adds to unless Settings names one.
    private var lastUsedID = ShelfStash.mainID
    private var monitors: [Any] = []
    /// The look-up of every file that is under way.
    private var resolveTask: Task<Void, Never>?
    private var lastChangeCount = 0
    /// The current drag put file URLs on the pasteboard.
    private var fileDrag = false
    /// The drag started in an app Settings says to ignore.
    private var ignoredSource = false
    /// The drag started in one of Sysbar's own windows, such as a file dragged out of a stash.
    private var startedHere = false
    /// This drag already shook hard enough to open the picker.
    private var summoned = false
    /// Recent pointer samples for the shake, in seconds since launch.
    private var shakeSamples: [(time: TimeInterval, sample: DragShake.Sample)] = []

    init(preferences: Preferences) {
        self.preferences = preferences
        let store = ShelfStashStore(directory: ShelfStashStore.directory(parentStored: preferences.shelfLocation))
        self.store = store
        let loaded = store.load()
        var library = loaded.library
        if loaded.recovered { Self.log.error("The stashes file could not be read; it was kept as \(ShelfStashStore.corruptFilePrefix).") }
        if loaded.isFirstRun {
            // Shelves put away before stashes were named: their files that still exist go to Main, once.
            library.adopt(preferences.legacyShelfHistory)
            if library != loaded.library { Self.persist(library, in: store) }
        }
        self.library = library
        refreshFiles()
    }

    func sync() {
        if preferences.shelfEnabled {
            start()
        } else if !monitors.isEmpty {
            stop()
        }
    }

    func appWillTerminate() {
        stop()
    }

    // MARK: Drag detection

    private func start() {
        guard monitors.isEmpty else { return }
        lastChangeCount = NSPasteboard(name: .drag).changeCount
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event, inSysbar: false) }
        }) { monitors.append(monitor) }
        // A global monitor does not see events delivered to this app, such as a file dragged out of a stash.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event, inSysbar: true) }
            return event
        }) { monitors.append(monitor) }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if fileDrag { onFileDragEnded() }
        fileDrag = false
        summoned = false
        startedHere = false
        shakeSamples = []
    }

    private func observe(_ event: NSEvent, inSysbar: Bool) {
        switch event.type {
        case .leftMouseDown:
            summoned = false
            fileDrag = false
            shakeSamples = []
            startedHere = inSysbar
            ignoredSource = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                .map(preferences.shelfIgnoredApps.contains) ?? false
            // Only a change after this point is a new drag: a drag that started in Sysbar leaves its
            // files on the pasteboard without any event reaching here.
            lastChangeCount = NSPasteboard(name: .drag).changeCount
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
            if fileDrag { onFileDragEnded() }
            fileDrag = false
            summoned = false
            startedHere = false
            shakeSamples = []
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
        fileDrag = !ignoredSource && !startedHere && ShelfPasteboard.containsFileURLs(pasteboard)
        if fileDrag, preferences.shelfNotchEnabled { onFileDragBegan() }
    }

    /// The stashes, offered once per drag.
    private func summon() {
        summoned = true
        onSummon()
    }

    /// Files dropped on a tile of the picker. A new stash gets the next free name and is then shown
    /// for the user to name it.
    func drop(_ urls: [URL], on target: ShelfPickerLayout.Target) {
        switch target {
        case .stash(let id):
            add(urls, to: id)
        case .newStash:
            let id = createStash(startRenaming: true, reveal: false)
            add(urls, to: id)
            onReveal()
        }
    }

    // MARK: Reading

    var stashes: [ShelfStash] { library.stashes }
    var selected: ShelfStash { library.stash(selectedID) ?? library.main }
    var totalItemCount: Int { library.itemCount }
    var shortcutForNewStash: KeyShortcut? { preferences.shelfShortcuts["new"] }
    var shortcutForClipboard: KeyShortcut? { preferences.shelfShortcuts["clipboard"] }

    func state(of item: ShelfItem) -> FileState? {
        item.kind == .file ? fileStates[item.id] ?? .found(URL(fileURLWithPath: item.path)) : nil
    }

    // MARK: Changing stashes

    /// A new stash with the next free name and the least used colour, selected.
    @discardableResult
    func createStash(startRenaming: Bool, reveal: Bool) -> ShelfStash.ID {
        var id = ShelfStash.mainID
        commit { id = $0.create(reserved: [L("Main")], defaultName: { L("Stash %@", "\($0)") }) }
        selectedID = id
        deletingID = nil
        renamingID = startRenaming ? id : nil
        if reveal { onReveal() }
        return id
    }

    /// False when the name was refused: blank, or used by another stash.
    @discardableResult
    func rename(_ id: ShelfStash.ID, to name: String) -> Bool {
        var outcome = ShelfLibrary.RenameOutcome.notAllowed
        commit { outcome = $0.rename(id, to: name, reserved: [L("Main")]) }
        return outcome == .renamed || outcome == .unchanged
    }

    func recolor(_ id: ShelfStash.ID, to color: Int) {
        commit { $0.recolor(id, to: color) }
    }

    /// Asks to delete a stash that holds items; an empty one just goes.
    func requestDelete(_ stash: ShelfStash) {
        guard !stash.isMain else { return }
        if stash.items.isEmpty { return delete(stash.id) }
        // The question is asked on the stash's own page, so that is the one to show.
        selectedID = stash.id
        deletingID = stash.id
        let question = deleteQuestion(for: stash)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: question])
    }

    /// What the confirmation asks, which depends on whether Settings moves a deleted stash's items to Main.
    func deleteQuestion(for stash: ShelfStash) -> String {
        preferences.shelfDeleteMovesItems
            ? L("Delete %@? Its items move to Main.", stash.displayName)
            : L("Delete %@ and what it holds? Files stay where they are.", stash.displayName)
    }

    /// Deletes a stash; what it held goes to Main, or goes with it, as Settings says.
    func delete(_ id: ShelfStash.ID) {
        deletingID = nil
        let movesItems = preferences.shelfDeleteMovesItems
        commit { $0.delete(id, movingItemsToMain: movesItems) }
        if library.stash(selectedID) == nil { selectedID = ShelfStash.mainID }
        if lastUsedID == id { lastUsedID = ShelfStash.mainID }
        if renamingID == id { renamingID = nil }
        refreshFiles()
    }

    func select(_ id: ShelfStash.ID) {
        guard library.stash(id) != nil else { return }
        if id != selectedID { deletingID = nil }
        selectedID = id
    }

    // MARK: Changing items

    func add(_ urls: [URL], to id: ShelfStash.ID) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return NSSound.beep() }
        add(files.map { ShelfItem.file($0) }, to: id)
    }

    func add(_ items: [ShelfItem], to id: ShelfStash.ID) {
        var added: [ShelfItem] = []
        commit { added = $0.add(items, to: id) }
        guard !added.isEmpty else { return }
        lastUsedID = id
        resolve(added, replacingAll: false)
    }

    func remove(_ itemIDs: Set<UUID>, from id: ShelfStash.ID) {
        commit { $0.remove(itemIDs, from: id) }
    }

    func move(_ itemIDs: Set<UUID>, from source: ShelfStash.ID, to target: ShelfStash.ID) {
        var moved = 0
        commit { moved = $0.move(itemIDs, from: source, to: target) }
        if moved > 0 { lastUsedID = target }
    }

    /// What is on the clipboard, put in a stash: copied files, otherwise copied text. Reads the pasteboard
    /// itself, so it works with the clipboard history off. Goes to `id`, or to the stash Settings chose, or
    /// to the one that last took something, or Main. Beeps when there is nothing to add.
    func addClipboard(to id: ShelfStash.ID? = nil) {
        let items = Self.clipboardItems()
        guard !items.isEmpty else { return NSSound.beep() }
        add(items, to: id ?? ShelfDefaultStash.target(
            chosen: ShelfDefaultStash.chosen(stored: preferences.shelfDefaultStash), lastUsed: lastUsedID, in: library
        ))
    }

    private static func clipboardItems() -> [ShelfItem] {
        let pasteboard = NSPasteboard.general
        let files = ShelfPasteboard.fileURLs(on: pasteboard).filter(\.isFileURL)
        if !files.isEmpty { return files.map { ShelfItem.file($0) } }
        return pasteboard.string(forType: .string).flatMap { ShelfItem.text($0) }.map { [$0] } ?? []
    }

    // MARK: Files

    /// Looks every file up again, as a file may have been moved, renamed or deleted since. Bookmarks
    /// that went stale, and the paths and names of files that moved, are brought up to date and saved.
    /// Resolving can wait on the disk or a network volume, so it runs off the main thread.
    func refreshFiles() {
        resolve(library.stashes.flatMap(\.items), replacingAll: true)
    }

    /// Finds the file items among `items`, off the main thread, then keeps where they are and warms
    /// their icons. `replacingAll` forgets the places of files that are no longer in any stash.
    private func resolve(_ items: [ShelfItem], replacingAll: Bool) {
        let files = items.filter { $0.kind == .file }
        if replacingAll { resolveTask?.cancel() }
        guard !files.isEmpty || replacingAll else { return }
        let task = Task { [weak self] in
            let resolutions = await Task.detached(priority: .userInitiated) {
                let resolutions = files.map { ($0, $0.resolved()) }
                StashFileInfo.prefetch(resolutions.compactMap { $0.1.url?.path })
                return resolutions
            }.value
            guard !Task.isCancelled else { return }
            self?.apply(resolutions, replacingAll: replacingAll)
        }
        if replacingAll { resolveTask = task }
    }

    private func apply(_ resolutions: [(ShelfItem, ShelfItem.Resolution)], replacingAll: Bool) {
        var states = replacingAll ? [:] : fileStates
        var updated: [ShelfItem] = []
        for (item, resolution) in resolutions {
            states[item.id] = resolution.url.map(FileState.found) ?? .missing
            if resolution.item != item { updated.append(resolution.item) }
        }
        if fileStates != states { fileStates = states }
        guard !updated.isEmpty else { return }
        commit { $0.update(updated) }
    }

    // MARK: Location

    /// Where the stashes file is now.
    var directory: URL { store.directory }

    /// Whether stashes are already saved below `parent`.
    static func holdsStashes(below parent: URL) -> Bool {
        ShelfStashStore(directory: ShelfStashStore.directory(parentStored: StorageLocation.storedValue(for: parent))).hasStashes
    }

    /// Keeps the stashes below `parent` from now on: the file is moved there, or, with `useExisting`,
    /// the stashes already there replace these and this file stays where it is. Nil when it worked,
    /// otherwise what went wrong, and then nothing has changed. The file is small, so this is done at once.
    func relocate(toParent parent: URL, useExisting: Bool) -> String? {
        let stored = StorageLocation.storedValue(for: parent)
        let target = ShelfStashStore(directory: ShelfStashStore.directory(parentStored: stored))
        guard target.directory != store.directory else { return nil }
        if useExisting {
            let loaded = target.load()
            library = loaded.library
            selectedID = ShelfStash.mainID
            renamingID = nil
            deletingID = nil
            lastUsedID = ShelfStash.mainID
            refreshFiles()
        } else {
            do {
                try store.moved(to: target)
            } catch {
                Self.log.error("Moving the stashes failed: \(error.localizedDescription)")
                return error.localizedDescription
            }
        }
        store = target
        preferences.shelfLocation = stored
        return nil
    }

    // MARK: Saving

    /// Applies a change to a copy and keeps it, so the tab and the disk never disagree for long.
    private func commit(_ change: (inout ShelfLibrary) -> Void) {
        var next = library
        change(&next)
        guard next != library else { return }
        library = next
        Self.persist(next, in: store)
    }

    private static func persist(_ library: ShelfLibrary, in store: ShelfStashStore) {
        do {
            try store.save(library)
        } catch {
            log.error("Saving the stashes failed: \(error.localizedDescription)")
        }
    }
}
