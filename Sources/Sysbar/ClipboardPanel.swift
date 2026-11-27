import AppKit
import SwiftUI
import SysbarCore

/// What the panel shows: the search, the kind filter, and which of the matching entries is chosen.
@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { selection = 0 } } }
    @Published var filter = ClipboardFilter.all { didSet { if filter != oldValue { selection = 0 } } }
    @Published var selection = 0
    /// Counts showings, so the search field takes the keyboard each time.
    @Published private(set) var presentations = 0

    /// The filter in effect: All when the chosen one has no entries left.
    func activeFilter(in entries: [ClipboardEntry]) -> ClipboardFilter {
        ClipboardHistory.availableFilters(in: entries).contains(filter) ? filter : .all
    }

    func results(in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        ClipboardHistory.matching(query, filter: activeFilter(in: entries), in: entries)
    }

    /// Chooses the filter at `position` among the offered ones (0 is All); false if there is none.
    func selectFilter(at position: Int, in entries: [ClipboardEntry]) -> Bool {
        let offered = ClipboardHistory.availableFilters(in: entries)
        guard offered.count > 1, offered.indices.contains(position) else { return false }
        filter = offered[position]
        return true
    }

    func reset() {
        query = ""
        filter = .all
        selection = 0
        presentations += 1
    }

    func move(by step: Int, count: Int) {
        guard count > 0 else { return }
        selection = min(max(selection + step, 0), count - 1)
    }
}

/// The clipboard history beside the pointer: type to search, arrows to choose, Return to copy,
/// Escape to close. It takes the keyboard without bringing Sysbar forward, so the app being pasted
/// into stays active, and it closes as soon as anything else is clicked.
@MainActor
final class ClipboardPanel: NSPanel {
    private static let size = NSSize(width: 360, height: 440)
    private static let corner: CGFloat = 16

    private unowned let controller: ClipboardController
    private let model = ClipboardPanelModel()
    private var keyMonitor: Any?
    private var clickMonitors: [Any] = []

    init(controller: ClipboardController) {
        self.controller = controller
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let history = NSHostingView(rootView: ClipboardHistoryView(
            controller: controller, model: model,
            onPick: { [weak self] entry in self?.pick(entry) },
            onShelve: { [weak self] entry, stash in
                self?.controller.addToShelf(entry, stash: stash)
                self?.dismiss()
            }
        ))
        history.frame = NSRect(origin: .zero, size: Self.size)
        history.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: history.frame)
            glass.cornerRadius = Self.corner
            glass.contentView = history
            contentView = glass
        } else {
            let background = NSVisualEffectView(frame: history.frame)
            background.material = .popover
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = Self.corner
            background.layer?.cornerCurve = .continuous
            background.layer?.masksToBounds = true
            background.addSubview(history)
            contentView = background
        }
        setAccessibilityLabel(L("Clipboard History"))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        model.reset()
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(ShelfFiles.origin(size: frame.size, near: cursor, visible: visible))
        }
        orderFrontRegardless()
        makeKey()
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return handled ? nil : event
            }
        }
        watchClicks()
    }

    /// A click outside closes it. Losing key status is not enough: opened from the notch's panel
    /// it may never have become key, and would then stay on screen.
    private func watchClicks() {
        guard clickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) { clickMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self else { return }
                self.dismiss()
            }
            return event
        }) { clickMonitors.append(monitor) }
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
        orderOut(nil)
    }

    /// A click anywhere else ends it.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    /// Answers the keys the list uses, returning true; everything else goes to the search field.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        // While an input method is composing, Return and Escape belong to it.
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        // ⌘1 to ⌘5 choose a filter by its place in the row, leaving typing to the search field.
        let chord = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if chord == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), digit >= 1 {
            if !model.selectFilter(at: digit - 1, in: controller.entries) { NSSound.beep() }
            return true
        }
        let results = model.results(in: controller.entries)
        let selected = results.indices.contains(model.selection) ? results[model.selection] : nil
        switch event.keyCode {
        case 53:
            dismiss()
        case 125:
            model.move(by: 1, count: results.count)
        case 126:
            model.move(by: -1, count: results.count)
        case 36, 76:
            if let selected { pick(selected) } else { NSSound.beep() }
        case 51 where event.modifierFlags.contains(.command):
            if let selected { controller.delete(selected) }
            model.move(by: 0, count: results.count - 1)
        default:
            return false
        }
        return true
    }

    private func pick(_ entry: ClipboardEntry) {
        if controller.copy(entry) { dismiss() }
    }
}

/// Search and the list of copies: in the shortcut's panel, and on the Clipboard tab.
struct ClipboardHistoryView: View {
    @ObservedObject var controller: ClipboardController
    @ObservedObject var model: ClipboardPanelModel
    /// The shortcut's own panel: it answers Return and the arrows, so it says so at the bottom, and
    /// its search takes the keyboard. On the Clipboard tab neither, since that tab may be hidden.
    var isShortcutPanel = true
    /// On the panel's Clipboard tab, the most the list may take: it is as tall as its rows, and scrolls
    /// beyond that. Nil in the shortcut panel, whose list fills what the panel's fixed size leaves.
    var maxListHeight: CGFloat?
    let onPick: (ClipboardEntry) -> Void
    let onShelve: (ClipboardEntry, ShelfStash.ID) -> Void
    @FocusState private var searching: Bool

    /// Concentric with the shortcut panel's 16 pt corners, which the rows sit 6 pt inside.
    private static let rowCorner: CGFloat = 10
    /// A row's height (a title of one or two lines over its caption), and what lies between rows and
    /// around them, for sizing the list to its rows.
    private static let rowHeight: CGFloat = 46
    private static let rowSpacing: CGFloat = 2
    private static let listPadding: CGFloat = 6
    /// Above and below the note of an empty list on the tab, which is then compact.
    private static let emptyPadding: CGFloat = 20

    private static let dates: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        let results = model.results(in: controller.entries)
        let offered = ClipboardHistory.availableFilters(in: controller.entries)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search clipboard history"), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searching)
            }
            .padding(12)
            if offered.count > 1 { filterRow(offered) }
            Divider()
            if results.isEmpty {
                Text(controller.entries.isEmpty ? L("Nothing copied yet") : L("No matches"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, maxListHeight == nil ? 0 : Self.emptyPadding)
                    .frame(maxWidth: .infinity, maxHeight: maxListHeight == nil ? .infinity : nil)
            } else {
                list(results)
            }
            if isShortcutPanel {
                Divider()
                Text(L("Return copies the item, then paste it with ⌘V."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .onAppear { if isShortcutPanel { searching = true } }
        .onChange(of: model.presentations) { if isShortcutPanel { searching = true } }
    }

    /// One chip per kind that has entries: the chosen one with its name, the rest as icons.
    private func filterRow(_ offered: [ClipboardFilter]) -> some View {
        let active = model.activeFilter(in: controller.entries)
        return HStack(spacing: 4) {
            ForEach(Array(offered.enumerated()), id: \.element) { position, filter in
                let chosen = filter == active
                let name = ClipboardController.name(for: filter)
                Button { model.filter = filter } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ClipboardController.symbol(for: filter))
                        if chosen { Text(name).lineLimit(1) }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(chosen ? Color.primary : .secondary)
                    .background(Capsule().fill(chosen ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(isShortcutPanel && position < 9 ? "\(name) (⌘\(position + 1))" : name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: offered) { _, offered in
            if !offered.contains(model.filter) { model.filter = .all }
        }
    }

    private func list(_ results: [ClipboardEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        row(entry, selected: index == model.selection)
                            .id(entry.id)
                            .onHover { if $0 { model.selection = index } }
                    }
                }
                .padding(Self.listPadding)
            }
            .frame(height: maxListHeight.map {
                PageHeight.list(rows: results.count, rowHeight: Self.rowHeight, spacing: Self.rowSpacing, padding: Self.listPadding, room: $0)
            })
            .onChange(of: model.selection) { _, selection in
                guard results.indices.contains(selection) else { return }
                proxy.scrollTo(results[selection].id)
            }
        }
    }

    private func row(_ entry: ClipboardEntry, selected: Bool) -> some View {
        let subtitle = [controller.sourceName(of: entry), Self.dates.localizedString(for: entry.date, relativeTo: Date())]
            .compactMap { $0 }.joined(separator: " · ")
        return Button { onPick(entry) } label: {
            HStack(spacing: 10) {
                icon(entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.title(of: entry)).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Self.rowCorner, style: .continuous).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Copy")) { onPick(entry) }
            if controller.canStash(entry) {
                Menu(L("Add to Stash")) {
                    ForEach(controller.stashChoices()) { stash in
                        Button { onShelve(entry, stash.id) } label: {
                            // A coloured dot in a menu is drawn as a template; the name is what tells them apart.
                            Text(stash.displayName)
                        }
                    }
                }
            }
            Divider()
            Button(L("Delete"), role: .destructive) { controller.delete(entry) }
        }
    }

    @ViewBuilder
    private func icon(_ entry: ClipboardEntry) -> some View {
        if let image = controller.thumbnail(of: entry) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: entry.kind == .image ? .fill : .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: ClipboardController.symbol(for: entry.kind))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
    }
}
