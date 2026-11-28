import AppKit
import SysbarCore
import SwiftUI

/// How the island at the top of the screen is arranged, behaves and looks: which items are in its two
/// ears and when they show, what opens it, what fills it, how its icons look and which displays show it.
struct NotchSettingsPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .notch) {
            SettingsGroup(title: L("Preview"), footer: previewFooter) { NotchPreview(preferences: preferences) }

            SettingsGroup(
                title: NotchEar.left.title,
                footer: L("Drag a row to put it in another place or on the other side, or use its menu. An item that shows only when open is not on the closed island; it appears in its place when the island opens.")
            ) { NotchEarRows(preferences: preferences, ear: .left) }

            SettingsGroup(
                title: NotchEar.right.title,
                footer: L("Every item is also a tab of the open island, so none can be hidden for good. To remove a feature, turn it off on its own page. While the heat warning is on, or the Mac is kept awake, a glyph for it shows here too.")
            ) { NotchEarRows(preferences: preferences, ear: .right) }

            SettingsGroup(title: L("System readouts"), footer: L("Which readouts, and in what order, is set on the Readouts page. Only as many as fit beside the notch, with the other items in the same ear, are shown; the rest are in the open panel.")) {
                SettingsRow(symbol: "number", title: L("Readouts shown")) {
                    Picker(L("Readouts shown"), selection: $preferences.notchLeftCount) {
                        ForEach(Preferences.earCountRange, id: \.self) {
                            Text($0 == 0 ? L("None") : "\($0)").tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(title: L("Behavior"), footer: L("With click, resting the pointer on the island does nothing; a click, or a feature's icon, opens it.") + " " + L("In full screen, the island hides until the pointer reaches it.")) {
                SettingsRow(symbol: "cursorarrow.rays", title: L("Open on")) {
                    segmented(L("Open on"), $preferences.notchOpening) { $0.title }
                }
                RowDivider()
                SettingsRow(symbol: "eye", title: L("Show the island")) {
                    menu(L("Show the island"), $preferences.notchVisibility) { $0.title }
                }
            }

            SettingsGroup(title: L("Appearance"), footer: L("Black merges with the notch; automatic uses glass on a display without one. Glass follows the system's light or dark look.") + " " + L("Monochrome draws the readouts and icons in one colour; the heat warning keeps its own. On a display without a notch, large is limited to what fits the menu bar's height.")) {
                SettingsRow(symbol: "circle.lefthalf.filled", title: L("Background")) {
                    menu(L("Background"), $preferences.notchBackground) { $0.title }
                }
                RowDivider()
                SettingsRow(symbol: "paintpalette", title: L("Icon colors")) {
                    segmented(L("Icon colors"), $preferences.notchIconStyle) { $0.title }
                }
                RowDivider()
                SettingsRow(symbol: "textformat.size", title: L("Icon size")) {
                    segmented(L("Icon size"), $preferences.notchIconSize) { $0.title }
                }
            }

            SettingsGroup(title: L("Displays"), footer: L("A display without a notch gets a capsule at the top centre. With all displays, each has its own island, and opening one leaves the others closed.")) {
                SettingsRow(symbol: "display.2", title: L("Show on")) {
                    menu(L("Show on"), $preferences.notchDisplays) { $0.title }
                }
            }
        }
    }

    private var previewFooter: String? {
        preferences.sysbarPlacement == .notch ? nil : L("Takes effect once Sysbar is shown at the top of the screen, under General.")
    }

    private func menu<Value: Hashable & CaseIterable>(
        _ title: String, _ selection: Binding<Value>, label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func segmented<Value: Hashable & CaseIterable>(
        _ title: String, _ selection: Binding<Value>, label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

extension NotchDisplayChoice {
    var title: String {
        switch self {
        case .builtIn: L("Built-in display only")
        case .all: L("All displays")
        case .active: L("Display with the active menu bar")
        }
    }
}

extension NotchBackground {
    var title: String {
        switch self {
        case .automatic: L("Automatic")
        case .black: L("Black")
        case .glass: L("Glass")
        }
    }
}

extension NotchIconStyle {
    var title: String {
        switch self {
        case .colored: L("Colored")
        case .monochrome: L("Monochrome")
        }
    }
}

extension NotchIconSize {
    var title: String {
        switch self {
        case .small: L("Small")
        case .medium: L("Medium")
        case .large: L("Large")
        }
    }
}

extension NotchIslandVisibility {
    var title: String {
        switch self {
        case .always: L("Always")
        case .pointer: L("Only when the pointer is on it")
        }
    }
}

extension NotchOpening {
    var title: String {
        switch self {
        case .hover: L("Hover")
        case .click: L("Click")
        }
    }
}
