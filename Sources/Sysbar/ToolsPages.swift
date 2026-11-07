import SysbarCore
import SwiftUI

/// The temperature button in the popover, its unit, and the helper that sets fan speeds.
struct FansPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var helper: HelperConnection

    var body: some View {
        SettingsPageScaffold(page: .fans) {
            SettingsGroup(
                title: L("Top bar buttons"),
                footer: L("Hiding the button also gives the fans back to macOS.")
            ) {
                // The temperature button shows on any Mac that can read its sensors, fans or not.
                SettingsRow(symbol: "fan", title: L("Temperature and fans")) {
                    RowToggle(isOn: $preferences.showsFanButton)
                }
            }

            SettingsGroup(title: L("Units")) {
                SettingsRow(symbol: "thermometer.medium", title: L("Temperature")) {
                    Picker(L("Temperature"), selection: $preferences.temperatureUnit) {
                        Text(L("Celsius")).tag(TemperatureUnit.celsius)
                        Text(L("Fahrenheit")).tag(TemperatureUnit.fahrenheit)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            HelperGroup(helper: helper)
        }
    }
}

/// The keep-awake button in the popover, and on a laptop the helper that keeps it awake with the
/// lid closed.
struct KeepAwakePage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var helper: HelperConnection

    var body: some View {
        SettingsPageScaffold(page: .keepAwake) {
            SettingsGroup(
                title: L("Top bar buttons"),
                footer: L("Hiding the button also lets the Mac sleep again.")
            ) {
                SettingsRow(symbol: SettingsPage.keepAwake.symbol, title: KeepAwakeController.title) {
                    RowToggle(isOn: $preferences.showsKeepAwakeButton)
                }
            }

            if KeepAwakeController.hasLid { HelperGroup(helper: helper) }
        }
    }
}

/// The floating shelf that gathers files while they are dragged.
struct ShelfPage: View {
    @ObservedObject var preferences: Preferences
    @State private var editingShortcuts = false
    @State private var editingIgnored = false

    var body: some View {
        SettingsPageScaffold(page: .shelf) {
            SettingsGroup(footer: L("The shelf only remembers where files are; nothing is copied.")) {
                SettingsRow(symbol: "tray.and.arrow.down", title: L("File shelf"), subtitle: L("Holds files while you drag them")) {
                    RowToggle(isOn: $preferences.shelfEnabled)
                }
                RowDivider()
                SettingsRow(symbol: "menubar.rectangle", title: L("Show menu bar icon")) {
                    RowToggle(isOn: $preferences.showsShelfIcon)
                }
            }

            Group {
                SettingsGroup {
                    SettingsRow(symbol: "cursorarrow.motionlines", title: L("Activate with shake gesture"), subtitle: L("Shake the cursor while dragging.")) {
                        RowToggle(isOn: $preferences.shelfShake)
                    }
                    RowDivider(inset: 12)
                    SettingsRow(title: L("Sensitivity")) {
                        choice(L("Sensitivity"), $preferences.shelfSensitivity) { $0.title }
                    }
                    .disabled(!preferences.shelfShake)
                }

                SettingsGroup {
                    SettingsRow(symbol: "shift", title: L("Activate with modifier key"), subtitle: L("Hold a modifier key while dragging.")) {
                        RowToggle(isOn: $preferences.shelfModifierEnabled)
                    }
                    RowDivider(inset: 12)
                    SettingsRow(title: L("Modifier key")) {
                        choice(L("Modifier key"), $preferences.shelfModifier) { $0.title }
                    }
                    .disabled(!preferences.shelfModifierEnabled)
                }

                SettingsGroup {
                    SettingsRow(symbol: "keyboard", title: L("Keyboard shortcuts")) {
                        Button(L("Edit…")) { editingShortcuts = true }
                    }
                }

                SettingsGroup {
                    SettingsRow(
                        symbol: "macbook", title: L("Drop to notch"),
                        subtitle: ShelfNotch.screen == nil ? L("This Mac has no notch.") : L("Drag files to the notch at the top of the screen.")
                    ) {
                        RowToggle(isOn: $preferences.shelfNotchEnabled)
                    }
                    .disabled(ShelfNotch.screen == nil)
                    RowDivider(inset: 12)
                    SettingsRow(title: L("Drop zone")) {
                        choice(L("Drop zone"), $preferences.shelfNotchStyle) { $0.title }
                    }
                    .disabled(ShelfNotch.screen == nil || !preferences.shelfNotchEnabled)
                }

                SettingsGroup {
                    SettingsRow(symbol: "rectangle.inset.topright.filled", title: L("Default shelf location"), subtitle: L("For shelves not created by shaking.")) {
                        choice(L("Default shelf location"), $preferences.shelfPlacement) { $0.title }
                    }
                    RowDivider()
                    SettingsRow(symbol: "doc.badge.plus", title: L("Adding files behavior"), subtitle: L("What happens when files arrive from the clipboard or the notch.")) {
                        HStack(spacing: 8) {
                            choice(L("Adding files behavior"), $preferences.shelfAddBehavior) { $0.title }
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .help(L("Show in new shelf puts the files on a new shelf next to the others. Add to current shelf adds them to the shelf you used last."))
                                .accessibilityLabel(L("Show in new shelf puts the files on a new shelf next to the others. Add to current shelf adds them to the shelf you used last."))
                        }
                    }
                    RowDivider()
                    SettingsRow(symbol: "nosign", title: L("Ignored applications")) {
                        Button(L("Edit…")) { editingIgnored = true }
                    }
                }
            }
            .disabled(!preferences.shelfEnabled)
        }
        .sheet(isPresented: $editingShortcuts) {
            ShelfShortcutsSheet(preferences: preferences) { editingShortcuts = false }
        }
        .sheet(isPresented: $editingIgnored) {
            ShelfIgnoredAppsSheet(preferences: preferences) { editingIgnored = false }
        }
    }

    private func choice<Value: Hashable & CaseIterable>(
        _ title: String, _ selection: Binding<Value>, label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// Setting up, approving or removing Sysbar's helper, on the pages of the tools that use it.
struct HelperGroup: View {
    @ObservedObject var helper: HelperConnection

    var body: some View {
        if helper.isNeeded {
            SettingsGroup(title: L("Helper"), footer: helper.setupError ?? footer) {
                SettingsRow(symbol: "lock.shield", title: L("Sysbar's helper"), subtitle: status) {
                    action
                }
            }
        }
    }

    private var status: String {
        switch helper.state {
        case .ready: L("Set up; used from the popover")
        case .needsApproval: L("Waiting for approval in System Settings")
        case .notInstalled: L("Not set up")
        case .unavailable: L("Needs a signed copy of Sysbar")
        }
    }

    private var footer: String {
        L("The helper runs only while Sysbar uses it and can only set fan speeds and keep the Mac awake with the lid closed. Both end when Sysbar quits or crashes.")
    }

    @ViewBuilder
    private var action: some View {
        switch helper.state {
        case .ready:
            HStack {
                if helper.isUnresponsive { Button(L("Set up again")) { Task { await helper.reinstall() } } }
                Button(L("Remove")) { Task { await helper.uninstall() } }
            }
        case .needsApproval: Button(L("Open System Settings")) { helper.openApprovalSettings() }
        case .notInstalled: Button(L("Set up…")) { helper.install() }
        case .unavailable: EmptyView()
        }
    }
}
