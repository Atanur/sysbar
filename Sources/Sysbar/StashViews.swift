import AppKit
import SwiftUI
import SysbarCore

/// The stash's name, shown on its tab and settings page.
enum Stash {
    static var title: String { L("Stash") }
    static let symbol = "archivebox"
}

/// The Stash tab: a tab bar of the stashes, each with its colour and name, and the items of the one
/// selected below it, as wide as the panel. Dropped files go to the selected stash. The tab is as tall
/// as the items it holds, up to `maxHeight`, and the list scrolls beyond that; an empty stash is compact.
struct StashPage: View {
    /// What the tab bar, the stash's header and their insets take of the page's height.
    private static let chrome: CGFloat = 96

    @ObservedObject var shelf: ShelfController
    @ObservedObject var preferences: Preferences
    let isWide: Bool
    /// The most the whole page may be as tall as.
    let maxHeight: CGFloat
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StashTabBar(shelf: shelf, isWide: isWide)
            StashDetail(shelf: shelf, listRoom: maxHeight - Self.chrome, onClose: onClose)
        }
        .onAppear { shelf.refreshFiles() }
    }
}

/// One tab for each stash, scrolling sideways when there are many, and a button that makes a new one.
/// Wide, the button says so and shows its shortcut; narrow, it is a plus.
struct StashTabBar: View {
    let shelf: ShelfController
    @ObservedObject private var stashes: ShelfController
    let isWide: Bool

    init(shelf: ShelfController, isWide: Bool) {
        self.shelf = shelf
        self.isWide = isWide
        _stashes = ObservedObject(wrappedValue: shelf)
    }

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stashes.stashes) { StashTab(shelf: shelf, stash: $0) }
                }
            }
            newStashButton
        }
    }

    private var newStashButton: some View {
        Button {
            shelf.createStash(startRenaming: true, reveal: false)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").accessibilityHidden(true)
                if isWide {
                    Text(L("New Stash"))
                    if let shortcut = shelf.shortcutForNewStash { Text(shortcut.display).font(.caption).foregroundStyle(.tertiary) }
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L("New Stash"))
        .accessibilityLabel(L("New Stash"))
    }
}

/// Reads dropped file URLs, which arrive one by one and off the main thread.
enum StashDrop {
    static func loadFiles(_ providers: [NSItemProvider], then done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        // Filled by position, so the files land in the order they were dropped in.
        var found = [URL?](repeating: nil, count: providers.count)
        for (index, provider) in providers.enumerated() {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    found[index] = url
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { done(found.compactMap { $0 }) } }
    }
}

/// The Clipboard tab: the copies, searchable, each put back on the clipboard by a click. It is on offer
/// while the clipboard history is on, whether or not the stash is. Its list is as tall as its rows, up
/// to what `maxHeight` leaves after the search and the row below.
struct ClipboardPage: View {
    /// What the search, the filters and the row below the list take of the page's height.
    private static let chrome: CGFloat = 132

    @ObservedObject var clipboard: ClipboardController
    @ObservedObject var preferences: Preferences
    let isWide: Bool
    let maxHeight: CGFloat
    let onClose: () -> Void
    @StateObject private var model = ClipboardPanelModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClipboardHistoryView(
                controller: clipboard, model: model, isShortcutPanel: false, maxListHeight: maxHeight - Self.chrome,
                onPick: { if clipboard.copy($0) { onClose() } },
                onShelve: { entry, stash in clipboard.addToShelf(entry, stash: stash) }
            )
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            HStack {
                PanelRow(symbol: "magnifyingglass", title: L("Show Clipboard History…"), shortcut: preferences.clipboardShortcut) {
                    onClose()
                    DispatchQueue.main.async { clipboard.showPanel() }
                }
                if !clipboard.entries.isEmpty {
                    Button(L("Clear"), action: clipboard.clear)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(L("Clear Clipboard History"))
                        .accessibilityLabel(L("Clear Clipboard History"))
                }
            }
        }
    }
}

/// One line in the panel, like a menu item: a symbol, a title and the shortcut that does the same.
private struct PanelRow: View {
    let symbol: String
    let title: String
    var shortcut: KeyShortcut?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let shortcut { Text(shortcut.display).font(.caption).foregroundStyle(.tertiary) }
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering && isEnabled ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}
