import AppKit
import Quartz
import SwiftUI
import SysbarCore

/// One tab of the stash tab bar: its colour dot, name and item count. Click to show it,
/// double-click or the menu to rename it, and drop files on it to add them. The menu also recolours
/// and deletes it.
struct StashTab: View {
    let shelf: ShelfController
    @ObservedObject private var tab: StashTabState
    let stash: ShelfStash
    @State private var draft = ""
    @State private var dropTargeted = false
    @FocusState private var editing: Bool

    init(shelf: ShelfController, stash: ShelfStash) {
        self.shelf = shelf
        self.stash = stash
        _tab = ObservedObject(wrappedValue: shelf.tab)
    }

    private var isSelected: Bool { tab.selectedID == stash.id }
    private var isRenaming: Bool { tab.renamingID == stash.id }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(stash.tint).frame(width: 10, height: 10).accessibilityHidden(true)
            if isRenaming {
                TextField(L("Name"), text: $draft)
                    .textFieldStyle(.plain)
                    .focused($editing)
                    .onSubmit { finishRenaming(keepingEdit: true) }
                    .onExitCommand { shelf.renamingID = nil }
                    .frame(minWidth: 60, maxWidth: 140)
                    .accessibilityLabel(L("Name"))
            } else {
                Text(stash.displayName).lineLimit(1).truncationMode(.tail)
                Text("\(stash.items.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .font(.callout.weight(isSelected ? .semibold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(shape.fill(Color.primary.opacity(dropTargeted ? 0.16 : isSelected ? 0.10 : 0.0001)))
        .overlay(shape.strokeBorder(Color.primary.opacity(dropTargeted ? 0.45 : 0), lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(count: 2) { beginRenaming() }
        // Simultaneous, so a click selects at once instead of waiting out the double-click interval.
        .simultaneousGesture(TapGesture().onEnded { shelf.select(stash.id) })
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            StashDrop.loadFiles(providers) { urls in
                shelf.add(urls, to: stash.id)
                shelf.select(stash.id)
            }
            return true
        }
        .contextMenu { menu }
        .onChange(of: tab.renamingID) { old, new in
            // Another stash was chosen for renaming while this one was being edited: keep what was typed.
            if old == stash.id, let new, new != stash.id { _ = shelf.rename(stash.id, to: draft) }
            guard new == stash.id else { return }
            draft = stash.name
            focusField()
        }
        .onChange(of: editing) { _, focused in
            // Clicking away keeps a good name and drops a refused one.
            if !focused, isRenaming { finishRenaming(keepingEdit: false) }
        }
        .onAppear {
            if isRenaming {
                draft = stash.name
                focusField()
            }
        }
        .help(stash.displayName)
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel([stash.displayName, stash.countText].joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { shelf.select(stash.id) }
        .accessibilityActions {
            if !stash.isMain {
                Button(L("Rename")) { beginRenaming() }
                Button(L("Delete Stash…")) { shelf.requestDelete(stash) }
            }
            ForEach(0..<ShelfStash.paletteSize, id: \.self) { index in
                Button("\(L("Color")): \(StashStyle.colorName(index))") { shelf.recolor(stash.id, to: index) }
            }
        }
    }

    private var shape: Capsule { Capsule() }

    @ViewBuilder
    private var menu: some View {
        if !stash.isMain { Button(L("Rename")) { beginRenaming() } }
        Menu(L("Color")) {
            ForEach(0..<ShelfStash.paletteSize, id: \.self) { index in
                Button { shelf.recolor(stash.id, to: index) } label: {
                    if index == stash.color {
                        Label(StashStyle.colorName(index), systemImage: "checkmark")
                    } else {
                        Text(StashStyle.colorName(index))
                    }
                }
            }
        }
        if !stash.isMain {
            Divider()
            Button(L("Delete Stash…"), role: .destructive) { shelf.requestDelete(stash) }
        }
    }

    /// The field is focused a moment after it appears: a focus asked for in the same update is dropped.
    private func focusField() {
        DispatchQueue.main.async { editing = true }
    }

    private func beginRenaming() {
        guard !stash.isMain else { return }
        shelf.select(stash.id)
        shelf.renamingID = stash.id
    }

    /// Saves the draft. A name that is refused stays in the field after Return, and is dropped on blur.
    private func finishRenaming(keepingEdit: Bool) {
        guard isRenaming else { return }
        if shelf.rename(stash.id, to: draft) {
            shelf.renamingID = nil
        } else if keepingEdit {
            NSSound.beep()
        } else {
            shelf.renamingID = nil
        }
    }
}

/// The items of one stash, with their count above them, a button that adds what is on the clipboard,
/// and a drop target for files. Empty, the drop target fills the space.
struct StashDetail: View {
    @ObservedObject var shelf: ShelfController
    @ObservedObject private var tab: StashTabState
    /// The stash chosen on the tab bar. Read here, where the choice is watched: passed in by the page,
    /// which watches only the stashes, it would stay the one shown first.
    private var stash: ShelfStash { shelf.selected }
    /// The most the item list may be as tall as; it is as tall as its items up to that, and scrolls beyond.
    let listRoom: CGFloat
    let onClose: () -> Void
    @State private var dropTargeted = false
    /// An item's row (measured: 29 pt of text and 8 pt of padding), and the gap between rows, for
    /// sizing the list to whole items. Rows are held to this height.
    private static let rowHeight: CGFloat = 37
    private static let rowSpacing: CGFloat = 1

    init(shelf: ShelfController, listRoom: CGFloat, onClose: @escaping () -> Void) {
        self.shelf = shelf
        self.listRoom = listRoom
        self.onClose = onClose
        _tab = ObservedObject(wrappedValue: shelf.tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if tab.deletingID == stash.id { confirmation }
            if stash.items.isEmpty {
                emptyZone
            } else {
                ScrollView {
                    LazyVStack(spacing: Self.rowSpacing) {
                        ForEach(stash.items) { StashItemRow(shelf: shelf, stash: stash, item: $0, onClose: onClose).frame(height: Self.rowHeight) }
                    }
                }
                .frame(height: PageHeight.list(rows: stash.items.count, rowHeight: Self.rowHeight, spacing: Self.rowSpacing, room: listRoom))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(dropTargeted ? 0.10 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(dropTargeted ? 0.45 : 0), lineWidth: 2))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            StashDrop.loadFiles(providers) { shelf.add($0, to: stash.id) }
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(stash.countText)
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button {
                shelf.addClipboard(to: stash.id)
            } label: {
                Label(L("Add Clipboard to Stash"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(L("Add Clipboard to Stash") + (shelf.shortcutForClipboard.map { " (\($0.display))" } ?? ""))
        }
    }

    /// Asked inline: a sheet or an alert would take the panel's focus, and the panel closes on that.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(shelf.deleteQuestion(for: stash)).font(.caption)
            HStack {
                Button(L("Cancel")) { shelf.deletingID = nil }
                Button(L("Delete"), role: .destructive) {
                    shelf.delete(stash.id)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.12)))
    }

    private var emptyZone: some View {
        VStack(spacing: 6) {
            Image(systemName: Stash.symbol).font(.system(size: 22))
            Text(L("Drop files here")).font(.callout.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.primary.opacity(0.25))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Drop files here"))
    }
}

/// One file, piece of text or link in a stash. Double-click opens a file or link and copies text;
/// dragging it out leaves it in the stash. The menu has Quick Look, Show in Finder, Move to and Remove,
/// and VoiceOver gets each as an action.
struct StashItemRow: View {
    @ObservedObject var shelf: ShelfController
    let stash: ShelfStash
    let item: ShelfItem
    let onClose: () -> Void
    @State private var hovering = false
    /// The icon and folder, once read; until then the cache may already have them.
    @State private var info: StashFileInfo.Entry?

    private var state: ShelfController.FileState? { shelf.state(of: item) }
    private var fileURL: URL? {
        if case .found(let url) = state { return url }
        return nil
    }
    private var isMissing: Bool { state == .missing }
    private var fileInfo: StashFileInfo.Entry? { fileURL.flatMap { info ?? StashFileInfo.cached($0.path) } }

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption2).foregroundStyle(isMissing ? Color.orange : Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: fileURL?.path) { await loadInfo() }
        .onTapGesture(count: 2) { open() }
        .onDrag { dragProvider }
        .contextMenu { menu }
        .help(item.kind == .file ? (fileURL?.path ?? item.path) : item.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.name, subtitle].joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            if item.kind == .file {
                Button(L("Quick Look")) { quickLook() }
                Button(L("Show in Finder")) { reveal() }
            } else {
                Button(L("Copy")) { copyText() }
            }
            ForEach(shelf.stashes.filter { $0.id != stash.id }) { target in
                Button("\(L("Move to")) \(target.displayName)") { shelf.move([item.id], from: stash.id, to: target.id) }
            }
            Button(L("Remove from stash")) { shelf.remove([item.id], from: stash.id) }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .file:
            if fileURL != nil {
                // The generic document icon stands in until the file's own is read.
                Image(nsImage: fileInfo?.icon ?? Self.placeholderIcon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed").font(.system(size: 18)).foregroundStyle(.orange)
            }
        case .text: Image(systemName: "text.alignleft").font(.system(size: 15)).foregroundStyle(.secondary)
        case .link: Image(systemName: "link").font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }

    private static let placeholderIcon = NSWorkspace.shared.icon(for: .data)

    /// Reads the file's icon and folder off the main thread, or takes them from the cache.
    private func loadInfo() async {
        guard let path = fileURL?.path else { return }
        if let known = StashFileInfo.cached(path) { return info = known }
        let entry = await Task.detached(priority: .userInitiated) { StashFileInfo.load(path) }.value
        if !Task.isCancelled { info = entry }
    }

    private var subtitle: String {
        switch item.kind {
        case .file:
            if isMissing { return L("File not found") }
            return fileInfo?.folder ?? ""
        case .text: return L("Text")
        case .link: return item.text
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(item.kind == .text ? L("Copy") : L("Open")) { open() }
            .disabled(isMissing)
        if item.kind == .file {
            Button(L("Quick Look")) { quickLook() }.disabled(isMissing)
            Button(L("Show in Finder")) { reveal() }.disabled(isMissing)
        } else {
            Button(L("Copy")) { copyText() }
        }
        let others = shelf.stashes.filter { $0.id != stash.id }
        if !others.isEmpty {
            Menu(L("Move to")) {
                ForEach(others) { target in
                    Button(target.displayName) { shelf.move([item.id], from: stash.id, to: target.id) }
                }
            }
        }
        Divider()
        Button(L("Remove from stash"), role: .destructive) { shelf.remove([item.id], from: stash.id) }
    }

    /// Dragging copies: the item stays in the stash.
    private var dragProvider: NSItemProvider {
        switch item.kind {
        case .file: fileURL.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .text: NSItemProvider(object: item.text as NSString)
        case .link: URL(string: item.text).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider(object: item.text as NSString)
        }
    }

    private func open() {
        switch item.kind {
        case .file: if let fileURL { NSWorkspace.shared.open(fileURL) }
        case .text: copyText()
        case .link: if let url = URL(string: item.text) { NSWorkspace.shared.open(url) }
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }

    private func reveal() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// The Quick Look panel is a window of its own, so the Sysbar panel goes first.
    private func quickLook() {
        guard let fileURL else { return }
        onClose()
        DispatchQueue.main.async { StashQuickLook.show(fileURL) }
    }
}

/// Quick Look asks for its items from outside the main actor.
private final class StashPreviewSource: NSObject, QLPreviewPanelDataSource {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}

@MainActor
enum StashQuickLook {
    private static let source = StashPreviewSource()

    static func show(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        source.urls = [url]
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = source
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}
