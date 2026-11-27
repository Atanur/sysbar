import SwiftUI
import SysbarCore

/// The clipboard history: whether it is kept, what and for how long, and where.
struct ClipboardSettingsPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var clipboard: ClipboardController
    @State private var editingIgnored = false
    @State private var confirmsClear = false
    /// What the history takes on disk; nil until it has been read.
    @State private var diskSize: Int64?

    var body: some View {
        SettingsPageScaffold(page: .clipboard) {
            SettingsGroup(
                footer: L("Copied text, links, images and files are kept on this Mac only. Copies that password managers mark as concealed are never kept. Turning this off deletes the history.")
            ) {
                SettingsRow(
                    symbol: "doc.on.clipboard", title: L("Clipboard history"),
                    subtitle: L("Keeps what you copy. The newest are on the Clipboard tab; a shortcut opens them all.")
                ) {
                    RowToggle(isOn: $preferences.clipboardHistoryEnabled)
                }
            }

            Group {
                SettingsGroup(
                    title: L("How long"),
                    footer: L("Copies older than this are deleted. An item copied again counts from then.")
                ) {
                    SettingsRow(title: L("Items to keep")) {
                        menu(L("Items to keep"), $preferences.clipboardHistoryLimit, ClipboardHistory.limits) { L("%@ items", "\($0)") }
                    }
                    RowDivider(inset: 12)
                    SettingsRow(title: L("Keep for")) {
                        menu(L("Keep for"), $preferences.clipboardRetention, ClipboardRetention.allCases) { $0.title }
                    }
                    RowDivider(inset: 12)
                    SettingsRow(
                        title: L("Keep repeated copies"),
                        subtitle: L("Off: copying the same thing again moves it to the top.")
                    ) {
                        RowToggle(isOn: $preferences.clipboardKeepsDuplicates)
                    }
                }

                SettingsGroup(
                    title: L("What to keep"),
                    footer: L("Rich text turned off is kept as plain text. Kinds that are off are not recorded at all.")
                ) {
                    ForEach(Array(ClipboardKind.allCases.enumerated()), id: \.element) { index, kind in
                        if index > 0 { RowDivider(inset: 12) }
                        SettingsRow(symbol: ClipboardController.symbol(for: kind), title: kind.title) {
                            RowToggle(isOn: kindBinding(kind))
                        }
                    }
                    RowDivider(inset: 12)
                    SettingsRow(title: L("Largest image")) {
                        menu(L("Largest image"), $preferences.clipboardImageLimit, ClipboardHistory.imageLimits) { L("%@ MB", "\($0)") }
                    }
                    .disabled(!preferences.clipboardKinds.contains(.image))
                }

                SettingsGroup(
                    title: L("Apps and shortcut"),
                    footer: L("Click a shortcut, then press the keys. Press Delete to clear it.")
                ) {
                    SettingsRow(symbol: "nosign", title: L("Ignored applications")) {
                        Button(L("Edit…")) { editingIgnored = true }
                    }
                    RowDivider(inset: 12)
                    SettingsRow(symbol: "keyboard", title: L("Show Clipboard History")) {
                        ShortcutRecorder(shortcut: Binding(
                            get: { preferences.clipboardShortcut },
                            set: { preferences.clipboardShortcut = $0 }
                        ))
                    }
                }

                SettingsGroup(
                    title: L("Storage"),
                    footer: L("Moving the folder moves the history with it. It is kept in a folder only your account can read.")
                ) {
                    StorageLocationRow(
                        noun: L("the clipboard history"), directory: clipboard.store.directory,
                        isDefault: preferences.clipboardLocation.isEmpty, isAvailable: clipboard.isFolderAvailable,
                        onChoose: chooseFolder, onReset: { change(to: StorageLocation.defaultParent) }
                    )
                    RowDivider(inset: 12)
                    SettingsRow(symbol: "internaldrive", title: L("History size"), subtitle: sizeText) {
                        Button(L("Clear Clipboard History")) { confirmsClear = true }
                            .disabled(clipboard.entries.isEmpty)
                    }
                }
            }
            .disabled(!preferences.clipboardHistoryEnabled)
        }
        .sheet(isPresented: $editingIgnored) {
            IgnoredAppsSheet(
                apps: $preferences.clipboardIgnoredApps,
                message: L("What you copy in these apps is not kept in the clipboard history.")
            ) { editingIgnored = false }
        }
        .confirmationDialog(L("Clear Clipboard History"), isPresented: $confirmsClear) {
            Button(L("Clear Clipboard History"), role: .destructive) { clipboard.clear() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Every copy in the history is deleted from this Mac."))
        }
        .task(id: clipboard.entries.count) { diskSize = await clipboard.diskSize() }
    }

    private var sizeText: String {
        let items = L("%@ items", "\(clipboard.entries.count)")
        guard let diskSize else { return items }
        return items + " · " + ByteCountFormatter.string(fromByteCount: diskSize, countStyle: .file)
    }

    private func kindBinding(_ kind: ClipboardKind) -> Binding<Bool> {
        Binding(
            get: { preferences.clipboardKinds.contains(kind) },
            set: { on in
                preferences.clipboardKinds = on
                    ? preferences.clipboardKinds.union([kind]) : preferences.clipboardKinds.subtracting([kind])
            }
        )
    }

    private func menu<Value: Hashable>(
        _ title: String, _ selection: Binding<Value>, _ values: [Value], label: @escaping (Value) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func chooseFolder() {
        guard let folder = StorageDialogs.chooseFolder(
            startingAt: StorageLocation.parent(stored: preferences.clipboardLocation),
            message: L("Choose where to keep the clipboard history. It gets a folder of its own there.")
        ) else { return }
        change(to: folder)
    }

    private func change(to parent: URL) {
        let target = ClipboardStore.directory(parentStored: StorageLocation.storedValue(for: parent))
        guard target != clipboard.store.directory else { return }
        guard let how = StorageDialogs.clipboardRelocation(
            currentHasHistory: clipboard.store.hasHistory, destinationHasHistory: ClipboardController.holdsHistory(below: parent)
        ) else { return }
        Task {
            if let failure = await clipboard.relocate(toParent: parent, how: how) { StorageDialogs.showFailure(failure) }
            diskSize = await clipboard.diskSize()
        }
    }
}

extension ClipboardRetention {
    var title: String {
        switch self {
        case .day: L("1 day")
        case .week: L("1 week")
        case .month: L("1 month")
        case .quarter: L("3 months")
        case .forever: L("Forever")
        }
    }
}

extension ClipboardKind {
    /// The name Settings gives the kind.
    var title: String {
        switch self {
        case .text: L("Text")
        case .link: L("Links")
        case .richText: L("Rich text")
        case .image: L("Images")
        case .files: L("Files")
        }
    }
}
