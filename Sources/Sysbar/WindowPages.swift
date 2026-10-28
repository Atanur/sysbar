import SysbarCore
import SwiftUI

/// How the popover arranges its cards. Which cards appear is chosen per device, on its page.
struct WindowLayoutPage: View {
    @ObservedObject var preferences: Preferences
    /// Opens this Mac's page, where its cards are chosen.
    let showThisMac: () -> Void

    var body: some View {
        SettingsPageScaffold(page: .windowLayout) {
            SettingsGroup {
                SettingsRow(symbol: "square.grid.2x2", title: L("Card layout"), subtitle: layoutDetail) {
                    Picker(L("Card layout"), selection: $preferences.cardLayout) {
                        ForEach(CardLayoutMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(footer: L("Each device's page, under Devices, sets which cards its tab shows and in what order.")) {
                SettingsRow(symbol: "rectangle.stack", title: L("Cards"), subtitle: L("Chosen for each device")) {
                    Button(L("Show this Mac's cards"), action: showThisMac)
                }
            }
        }
    }

    private var layoutDetail: String {
        switch preferences.cardLayout {
        case .automatic: L("Two columns for an even number of cards, one for an odd number")
        case .oneColumn: L("Cards stack in a single list")
        case .twoColumns: L("Always side by side")
        }
    }
}

/// The table of the busiest apps under the cards, and its columns.
struct AppsTablePage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .appsTable, animating: AnyHashable(preferences.showsApps)) {
            SettingsGroup(title: L("Top apps")) {
                SettingsRow(symbol: "list.bullet", title: L("Show table")) {
                    RowToggle(isOn: $preferences.showsApps)
                }
                RowDivider()
                SettingsRow(symbol: "number", title: L("Row count")) {
                    Stepper(value: $preferences.appRows, in: Preferences.appRowRange) {
                        Text("\(preferences.appRows)").monospacedDigit().frame(minWidth: 20, alignment: .trailing)
                    }
                    .disabled(!preferences.showsApps)
                    .accessibilityLabel(L("Row count"))
                    .accessibilityValue("\(preferences.appRows)")
                }
            }

            SettingsGroup(title: L("Table columns"), footer: L("At least one column must stay visible.")) {
                ForEach(Array(AppSortKey.allCases.enumerated()), id: \.element) { index, column in
                    if index > 0 { RowDivider() }
                    SettingsRow(symbol: column.symbol, title: column.columnTitle) {
                        RowToggle(isOn: Binding(
                            get: { preferences.isColumnVisible(column) },
                            set: { _ in preferences.toggleColumn(column) }
                        ))
                        .disabled(!preferences.showsApps || preferences.isColumnLocked(column))
                    }
                }
            }
        }
    }
}

extension CardLayoutMode {
    var title: String {
        switch self {
        case .automatic: L("Automatic")
        case .oneColumn: L("One column")
        case .twoColumns: L("Two columns")
        }
    }
}
