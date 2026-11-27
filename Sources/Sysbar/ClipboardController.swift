import AppKit
import ImageIO
import OSLog
import SysbarCore

/// Keeps what is copied: text, links, rich text, images and files, newest first, on this Mac only.
/// A feature of its own, independent of the stash. macOS has no notice for a clipboard change, so the
/// change count is read twice a second; reading it is cheap and needs no permission. Copies that
/// password managers mark as concealed, and those made in apps Settings lists, are never kept; Settings
/// also chooses the kinds kept, for how long, and where.
@MainActor
final class ClipboardController: ObservableObject {
    private static let log = Logger(subsystem: "com.atanur.sysbar", category: "clipboard")
    private static let pollInterval: TimeInterval = 0.5
    private static let thumbnailSide: CGFloat = 64
    private static let pollsPerMinute = 120

    @Published private(set) var entries: [ClipboardEntry] = []

    /// How the history moves when its folder changes.
    enum Relocation {
        /// Carry the history to the new folder.
        case move
        /// Begin an empty history in the new folder and delete the old one.
        case startFresh
        /// Use the history the new folder already holds, and delete the old one.
        case useExisting
    }

    /// Set by the owner: puts items from the history in a stash.
    var onAddToShelf: ([ShelfItem], ShelfStash.ID) -> Void = { _, _ in }
    /// Set by the owner: the stashes an item can go into; none while the stash is off.
    var stashChoices: () -> [ShelfStash] = { [] }

    private let preferences: Preferences
    private(set) var store: ClipboardStore
    /// The history is being carried to another folder: nothing is read or saved until it is there.
    private var isMoving = false
    private var polls = 0
    private var timer: Timer?
    private var lastChangeCount = 0
    private var lastFrontmost: String?
    private var loaded = false
    private var wasEnabled: Bool?
    private var thumbnails: [UUID: NSImage] = [:]
    /// Looked up once per app, including apps that are no longer installed.
    private var appNames: [String: String?] = [:]
    /// Made the first time it is shown.
    private var panel: ClipboardPanel?

    init(preferences: Preferences) {
        self.preferences = preferences
        store = ClipboardStore(directory: ClipboardStore.directory(parentStored: preferences.clipboardLocation))
    }

    var isRunning: Bool { timer != nil }

    /// Starts or stops keeping copies to match Settings. History turned off is deleted.
    func sync() {
        if preferences.clipboardHistoryEnabled {
            start()
            trim(to: preferences.clipboardHistoryLimit)
            pruneExpired()
        } else {
            stop()
        }
        // Once per change to off, and at a launch with it off, in case anything was left on disk.
        if !preferences.clipboardHistoryEnabled, wasEnabled != false {
            clear()
            loaded = false
        }
        wasEnabled = preferences.clipboardHistoryEnabled
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.dismiss()
    }

    private func start() {
        guard timer == nil else { return }
        if !loaded {
            entries = store.load()
            loaded = true
        }
        // What is already on the clipboard was copied while nobody was watching.
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard !isMoving else { return }
        // Once a minute: copies that have outlived their time.
        polls += 1
        if polls % Self.pollsPerMinute == 0 { pruneExpired() }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // The copy happened at most one poll ago, maybe in the app that was in front then.
        let previous = lastFrontmost
        lastFrontmost = frontmost
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !ClipboardPrivacy.isPrivate(types: types) else { return }
        // Apps may name themselves on the clipboard (nspasteboard.org); otherwise the one in front.
        let declared = pasteboard.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        let source = declared.flatMap { $0.isEmpty ? nil : $0 } ?? frontmost
        let ignored = preferences.clipboardIgnoredApps
        if [source, frontmost, previous].contains(where: { $0.map(ignored.contains) ?? false }) { return }
        guard let capture = Self.capture(
            pasteboard, types: types, source: source,
            allowed: preferences.clipboardKinds, maxImageBytes: ClipboardHistory.imageBytes(megabytes: preferences.clipboardImageLimit)
        ) else { return }
        add(capture.entry, data: capture.data)
    }

    /// The entry for what is on `pasteboard`, and the image or rich text to keep beside it. Kinds
    /// Settings turns off are skipped, and rich text turned off is kept as plain text.
    private static func capture(
        _ pasteboard: NSPasteboard, types: [String], source: String?, allowed: Set<ClipboardKind>, maxImageBytes: Int
    ) -> (entry: ClipboardEntry, data: Data?)? {
        let text = pasteboard.string(forType: .string)
        guard let found = ClipboardKind.of(types: types, text: text),
              let kind = ClipboardRecording.kept(found, allowed: allowed) else { return nil }
        let now = Date()
        switch kind {
        case .files:
            let paths = ShelfPasteboard.fileURLs(on: pasteboard).map(\.path)
            guard !paths.isEmpty else { return nil }
            return (ClipboardEntry(kind: .files, paths: paths, fingerprint: ClipboardEntry.fingerprint(paths: paths), source: source, date: now), nil)
        case .text, .link, .richText:
            guard var text, text.utf16.count <= ClipboardHistory.maxTextLength else { return nil }
            if kind == .link { text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let fingerprint = ClipboardEntry.fingerprint(text: text)
            if kind == .richText, let rtf = pasteboard.data(forType: .rtf), rtf.count <= ClipboardHistory.maxRichTextBytes {
                return (ClipboardEntry(kind: .richText, text: text, fingerprint: fingerprint, source: source, date: now), rtf)
            }
            // Rich text too large to keep, gone already or turned off: its words are still worth having.
            let plain: ClipboardKind = kind == .link ? .link : .text
            return (ClipboardEntry(kind: plain, text: text, fingerprint: fingerprint, source: source, date: now), nil)
        case .image:
            guard let png = pngData(on: pasteboard), png.count <= maxImageBytes else { return nil }
            return (ClipboardEntry(kind: .image, fingerprint: ClipboardEntry.fingerprint(data: png), source: source, date: now), png)
        }
    }

    /// Screenshots arrive as PNG; most other apps write TIFF, which is kept as PNG to save space.
    private static func pngData(on pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let image = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")),
              let bitmap = NSBitmapImageRep(data: image) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func add(_ entry: ClipboardEntry, data: Data?) {
        if let data {
            do {
                try store.write(data, for: entry)
            } catch {
                Self.log.error("Could not keep a copied item: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        let change = ClipboardHistory.adding(
            entry, to: entries, limit: preferences.clipboardHistoryLimit, keepingDuplicates: preferences.clipboardKeepsDuplicates
        )
        forget(change.dropped)
        entries = change.kept
        save()
    }

    /// Deletes the copies older than Settings keeps them.
    private func pruneExpired(now: Date = Date()) {
        let change = ClipboardHistory.expired(entries, keeping: preferences.clipboardRetention, now: now)
        guard !change.dropped.isEmpty else { return }
        forget(change.dropped)
        entries = change.kept
        save()
    }

    private func trim(to limit: Int) {
        let change = ClipboardHistory.trimmed(entries, to: limit)
        guard !change.dropped.isEmpty else { return }
        forget(change.dropped)
        entries = change.kept
        save()
    }

    private func forget(_ dropped: [ClipboardEntry]) {
        store.remove(dropped)
        dropped.forEach { thumbnails[$0.id] = nil }
    }

    private func save() {
        guard !isMoving else { return }
        do {
            try store.save(entries)
        } catch {
            Self.log.error("Could not save the clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Actions

    /// Puts an entry back on the clipboard, ready to paste, and moves it to the top. False when its
    /// image or files are gone.
    @discardableResult
    func copy(_ entry: ClipboardEntry) -> Bool {
        let pasteboard = NSPasteboard.general
        switch entry.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(entry.text, forType: .string)
        case .link:
            pasteboard.clearContents()
            pasteboard.setString(entry.text, forType: .string)
            pasteboard.setString(entry.text, forType: .URL)
        case .richText:
            guard let rtf = store.data(for: entry) else { return missing(entry) }
            pasteboard.clearContents()
            pasteboard.setData(rtf, forType: .rtf)
            pasteboard.setString(entry.text, forType: .string)
        case .image:
            guard let png = store.data(for: entry) else { return missing(entry) }
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            // Many apps only read TIFF.
            if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        case .files:
            let urls = existingFiles(of: entry)
            guard !urls.isEmpty else { return missing(entry) }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
        }
        // This copy is ours: it must not come back as a new entry.
        lastChangeCount = pasteboard.changeCount
        entries = ClipboardHistory.promoting(entry.id, in: entries, at: Date())
        save()
        return true
    }

    private func missing(_ entry: ClipboardEntry) -> Bool {
        NSSound.beep()
        delete(entry)
        return false
    }

    /// Files, links and text (rich text as plain text) can go in a stash; images cannot. Nothing can
    /// while the stash is off.
    func canStash(_ entry: ClipboardEntry) -> Bool {
        entry.kind != .image && !stashChoices().isEmpty
    }

    func addToShelf(_ entry: ClipboardEntry, stash: ShelfStash.ID) {
        let items: [ShelfItem]
        switch entry.kind {
        case .files: items = existingFiles(of: entry).map { ShelfItem.file($0) }
        case .text, .link, .richText: items = ShelfItem.text(entry.text).map { [$0] } ?? []
        case .image: items = []
        }
        guard !items.isEmpty else { return NSSound.beep() }
        onAddToShelf(items, stash)
    }

    func delete(_ entry: ClipboardEntry) {
        forget([entry])
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        store.removeAll()
        entries = []
        thumbnails = [:]
    }

    /// What the history takes on disk, in bytes. Read off the main thread.
    func diskSize() async -> Int64 {
        let store = store
        return await Task.detached { store.sizeOnDisk() }.value
    }

    /// Whether the history's folder is there: false while a drive it is on is not connected.
    var isFolderAvailable: Bool {
        FileManager.default.fileExists(atPath: store.directory.deletingLastPathComponent().path)
    }

    /// The history already saved below `parent`, if any.
    static func holdsHistory(below parent: URL) -> Bool {
        ClipboardStore(directory: ClipboardStore.directory(parentStored: StorageLocation.storedValue(for: parent))).hasHistory
    }

    /// Keeps the history below `parent` from now on. Nil when it worked, otherwise what went wrong, and
    /// then nothing has changed. Large histories take a while, so the copying is off the main thread.
    func relocate(toParent parent: URL, how: Relocation) async -> String? {
        let stored = StorageLocation.storedValue(for: parent)
        let target = ClipboardStore(directory: ClipboardStore.directory(parentStored: stored))
        let old = store
        guard target.directory != old.directory else { return nil }
        isMoving = true
        defer { isMoving = false }
        switch how {
        case .move:
            do {
                try await Task.detached { try old.moved(to: target) }.value
            } catch {
                Self.log.error("Could not move the history: \(error.localizedDescription, privacy: .public)")
                return error.localizedDescription
            }
        case .startFresh:
            old.removeAll()
            entries = []
        case .useExisting:
            old.removeAll()
            entries = target.load()
        }
        thumbnails = [:]
        store = target
        loaded = loaded || how == .useExisting
        preferences.clipboardLocation = stored
        return nil
    }

    func showPanel() {
        guard isRunning else { return NSSound.beep() }
        pruneExpired()
        let panel = panel ?? ClipboardPanel(controller: self)
        self.panel = panel
        panel.present()
    }

    // MARK: Presentation

    func existingFiles(of entry: ClipboardEntry) -> [URL] {
        entry.paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// One line naming the entry: its text, "Image", or the first file and how many more.
    func title(of entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text, .link, .richText:
            return ClipboardHistory.preview(of: entry.text)
        case .image:
            return L("Image")
        case .files:
            let name = entry.paths.first.map { FileManager.default.displayName(atPath: $0) } ?? ""
            return entry.paths.count > 1 ? "\(name) +\(entry.paths.count - 1)" : name
        }
    }

    /// The app it was copied in, by name.
    func sourceName(of entry: ClipboardEntry) -> String? {
        guard let source = entry.source else { return nil }
        if let name = appNames[source] { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source).map { url in
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(".app".count)) : name
        }
        appNames[source] = name
        return name
    }

    static func symbol(for kind: ClipboardKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .richText: "doc.richtext"
        case .image: "photo"
        case .files: "doc"
        }
    }

    static func symbol(for filter: ClipboardFilter) -> String {
        switch filter {
        case .all: "tray.full"
        case .text: symbol(for: ClipboardKind.text)
        case .link: symbol(for: ClipboardKind.link)
        case .image: symbol(for: ClipboardKind.image)
        case .files: symbol(for: ClipboardKind.files)
        }
    }

    static func name(for filter: ClipboardFilter) -> String {
        switch filter {
        case .all: L("All")
        case .text: L("Text")
        case .link: L("Links")
        case .image: L("Images")
        case .files: L("Files")
        }
    }

    /// A small picture of an image or the first file's icon; nil for text, which shows a symbol.
    func thumbnail(of entry: ClipboardEntry) -> NSImage? {
        if let cached = thumbnails[entry.id] { return cached }
        let image: NSImage?
        switch entry.kind {
        case .image:
            image = store.data(for: entry).flatMap(Self.downsampled)
        case .files:
            image = entry.paths.first.map { NSWorkspace.shared.icon(forFile: $0) }
        case .text, .link, .richText:
            image = nil
        }
        thumbnails[entry.id] = image
        return image
    }

    private static func downsampled(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSide * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}
