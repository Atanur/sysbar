import SwiftUI
import SysbarCore

extension Preferences {
    /// Whether the item has anything to show: the System item always does, a feature only while it
    /// is turned on, on its own page.
    func isAvailable(_ item: NotchItem) -> Bool {
        switch item {
        case .system: true
        case .stash: shelfEnabled
        case .clipboard: clipboardHistoryEnabled
        }
    }

    /// Every item that is available, for the preview and the ears.
    var availableNotchItems: Set<NotchItem> { Set(NotchItem.allCases.filter(isAvailable)) }
}

extension NotchItem {
    /// Why the item is not offered, as a sentence for its row.
    var unavailableReason: String {
        switch self {
        case .system: ""
        case .stash: L("Stash is off")
        case .clipboard: L("Clipboard history is off")
        }
    }
}

extension NotchEar {
    var title: String { self == .left ? L("Left of the notch") : L("Right of the notch") }
    /// The command that sends an item here.
    var moveTitle: String { self == .left ? L("Move to the left of the notch") : L("Move to the right of the notch") }
}

extension NotchVisibility {
    var title: String { self == .always ? L("Always") : L("Only when open") }
}

/// One ear's items as rows: each with its icon, its name and whether it shows on the closed island.
/// A row is dragged by its handle to a place in this ear or the other; the menu on every row does the
/// same without dragging, and the accessibility actions mirror it.
struct NotchEarRows: View {
    @ObservedObject var preferences: Preferences
    let ear: NotchEar

    private static let dragPrefix = "notchItem:"

    var body: some View {
        let items = preferences.notchEars.items(on: ear)
        Group {
            if items.isEmpty {
                SettingsRow(title: L("Nothing here"), subtitle: L("Drag an item here, or use an item's menu.")) { EmptyView() }
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 { RowDivider() }
                row(item, index: index, count: items.count)
            }
        }
        .contentShape(Rectangle())
        // Dropped anywhere else in the ear, an item goes last.
        .dropDestination(for: String.self) { dropped, _ in
            guard let item = Self.item(in: dropped) else { return false }
            update { $0.moving(item, to: ear) }
            return true
        }
    }

    private func row(_ item: NotchItem, index: Int, count: Int) -> some View {
        let section = item.section
        let available = preferences.isAvailable(item)
        return SettingsRow(
            symbol: section.symbol, title: section.title, subtitle: available ? nil : item.unavailableReason
        ) {
            Picker(L("Visibility of %@", section.title), selection: visibility(item)) {
                ForEach(NotchVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!available)
            Menu {
                Button(L("Move up")) { update { $0.shifting(item, by: -1) } }.disabled(index == 0)
                Button(L("Move down")) { update { $0.shifting(item, by: 1) } }.disabled(index == count - 1)
                Button(ear.opposite.moveTitle) { update { $0.moving(item, to: ear.opposite) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Arrange %@", section.title))
            .accessibilityLabel(L("Arrange %@", section.title))
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help(L("Drag to change the order"))
                .accessibilityHidden(true)
        }
        .opacity(available ? 1 : 0.55)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .draggable(Self.dragPrefix + item.rawValue) {
            Text(section.title).padding(.horizontal, 10).padding(.vertical, 6)
        }
        .dropDestination(for: String.self) { dropped, _ in
            guard let moved = Self.item(in: dropped) else { return false }
            update { $0.moving(moved, before: item) }
            return true
        }
        .contextMenu {
            Button(L("Move up")) { update { $0.shifting(item, by: -1) } }.disabled(index == 0)
            Button(L("Move down")) { update { $0.shifting(item, by: 1) } }.disabled(index == count - 1)
            Button(ear.opposite.moveTitle) { update { $0.moving(item, to: ear.opposite) } }
        }
        .accessibilityAction(named: L("Move up")) { update { $0.shifting(item, by: -1) } }
        .accessibilityAction(named: L("Move down")) { update { $0.shifting(item, by: 1) } }
        .accessibilityAction(named: ear.opposite.moveTitle) { update { $0.moving(item, to: ear.opposite) } }
    }

    private func visibility(_ item: NotchItem) -> Binding<NotchVisibility> {
        Binding(
            get: { preferences.notchEars.visibility(of: item) },
            set: { new in update { $0.setting(item, to: new) } }
        )
    }

    private func update(_ change: (NotchEarLayout) -> NotchEarLayout) {
        withAnimation(.snappy) { preferences.notchEars = change(preferences.notchEars) }
    }

    private static func item(in dropped: [String]) -> NotchItem? {
        dropped.first.flatMap { $0.hasPrefix(dragPrefix) ? String($0.dropFirst(dragPrefix.count)) : nil }
            .flatMap(NotchItem.init(rawValue:))
    }
}
