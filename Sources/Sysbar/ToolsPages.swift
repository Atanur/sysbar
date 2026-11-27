import SysbarCore
import SwiftUI

/// The temperature button of the System page, its unit, and the helper that sets fan speeds.
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

            SettingsGroup(
                title: L("Heat warning"),
                footer: L("The menu bar flags heat that is out of the ordinary, and the panel of the fan button opens on it. Early warns sooner and Late later; macOS slowing the Mac down counts at any setting except Off.")
            ) {
                SettingsRow(symbol: "thermometer.high", title: L("Warn about heat")) {
                    Picker(L("Warn about heat"), selection: $preferences.heatWarning) {
                        Text(L("Off")).tag(HeatWarning.off)
                        Text(L("Early")).tag(HeatWarning.early)
                        Text(L("Default")).tag(HeatWarning.standard)
                        Text(L("Late")).tag(HeatWarning.late)
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

/// The keep-awake button of the System page, and on a laptop the helper that keeps it awake with the
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

            SettingsGroup(
                title: L("Defaults"),
                footer: L("The switch in the Keep awake panel uses this length; the menu there offers the others. Keeping awake always ends when the battery runs low on battery power, so a closed lid in a bag cannot drain it.")
            ) {
                SettingsRow(symbol: "timer", title: L("When switched on")) {
                    Picker(L("When switched on"), selection: $preferences.keepAwakeSwitchDefault) {
                        Text(L("Until off")).tag(KeepAwakeSwitchDefault.untilOff)
                        Text(L("1 hour")).tag(KeepAwakeSwitchDefault.oneHour)
                        Text(L("4 hours")).tag(KeepAwakeSwitchDefault.fourHours)
                        Text(L("Last choice")).tag(KeepAwakeSwitchDefault.lastUsed)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                RowDivider(inset: 12)
                SettingsRow(symbol: "battery.25percent", title: L("End on low battery")) {
                    Picker(L("End on low battery"), selection: $preferences.keepAwakeLowBattery) {
                        ForEach(KeepAwakePolicy.lowBatteryChoices, id: \.self) {
                            Text(L("At %@ or less", Format.percent(Double($0) / 100))).tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsGroup(
                title: L("Mouse"),
                footer: L("Used while Move the mouse when idle is on in the Keep awake panel.")
            ) {
                SettingsRow(symbol: "cursorarrow.motionlines", title: L("Move the mouse after")) {
                    Picker(L("Move the mouse after"), selection: $preferences.keepAwakeMouseIdle) {
                        ForEach(MouseWander.idleChoices, id: \.self) { Text(Self.idleTitle($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            if KeepAwakeController.hasLid { HelperGroup(helper: helper) }
        }
    }
}

extension KeepAwakePage {
    fileprivate static func idleTitle(_ seconds: Double) -> String {
        switch seconds {
        case 30: L("30 seconds")
        case 60: L("1 minute")
        case 120: L("2 minutes")
        default: L("5 minutes")
        }
    }
}

/// The stash: named collections of files and text, and how files are dragged into them.
struct ShelfPage: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var shelf: ShelfController
    @State private var editingShortcuts = false
    @State private var editingIgnored = false

    var body: some View {
        SettingsPageScaffold(page: .shelf) {
            SettingsGroup(
                title: L("Top bar buttons"),
                footer: L("Stashes are kept until you delete them. A file in a stash is only remembered by where it is; nothing is copied. Hiding the button also turns the stash off.")
            ) {
                SettingsRow(symbol: Stash.symbol, title: Stash.title, subtitle: L("Keeps files and copies close at hand")) {
                    RowToggle(isOn: $preferences.shelfEnabled)
                }
            }

            Group {
                SettingsGroup {
                    SettingsRow(symbol: "cursorarrow.motionlines", title: L("Activate with shake gesture"), subtitle: L("Shake the cursor while dragging to choose a stash.")) {
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
                        subtitle: preferences.sysbarPlacement == .notch
                            ? L("Drag files to the notch, then drop them on a stash.")
                            : L("Needs Sysbar at the top of the screen.")
                    ) {
                        RowToggle(isOn: $preferences.shelfNotchEnabled)
                    }
                    .disabled(preferences.sysbarPlacement != .notch)
                }

                SettingsGroup {
                    SettingsRow(symbol: "nosign", title: L("Ignored applications")) {
                        Button(L("Edit…")) { editingIgnored = true }
                    }
                }

                SettingsGroup(
                    title: L("Stashes"),
                    footer: L("The shortcut adds to this stash; files dropped on a stash always go to that one. Deleting never touches the files themselves.")
                ) {
                    SettingsRow(symbol: "doc.on.clipboard", title: L("Add Clipboard to Stash goes to")) {
                        Picker(L("Add Clipboard to Stash goes to"), selection: defaultStash) {
                            Text(L("Last used stash")).tag("")
                            ForEach(shelf.stashes) { Text($0.displayName).tag($0.id.uuidString) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    RowDivider(inset: 12)
                    SettingsRow(symbol: "trash", title: L("When a stash is deleted")) {
                        Picker(L("When a stash is deleted"), selection: $preferences.shelfDeleteMovesItems) {
                            Text(L("Move its items to Main")).tag(true)
                            Text(L("Delete its items too")).tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }

                SettingsGroup(
                    title: L("Storage"),
                    footer: L("Moving the folder moves the stashes with it. It is kept in a folder only your account can read.")
                ) {
                    StorageLocationRow(
                        noun: L("the stashes"), directory: shelf.directory,
                        isDefault: preferences.shelfLocation.isEmpty,
                        isAvailable: FileManager.default.fileExists(atPath: shelf.directory.deletingLastPathComponent().path),
                        onChoose: chooseFolder, onReset: { change(to: StorageLocation.defaultParent) }
                    )
                }
            }
            .disabled(!preferences.shelfEnabled)
        }
        .sheet(isPresented: $editingShortcuts) {
            ShelfShortcutsSheet(preferences: preferences) { editingShortcuts = false }
        }
        .sheet(isPresented: $editingIgnored) {
            IgnoredAppsSheet(
                apps: $preferences.shelfIgnoredApps,
                message: L("Dragging files from these apps does not bring up a stash.")
            ) { editingIgnored = false }
        }
    }

    /// The stash id the shortcut uses, or empty for the last used; a stash that is gone shows as the last used.
    private var defaultStash: Binding<String> {
        Binding(
            get: {
                let stored = preferences.shelfDefaultStash
                return shelf.stashes.contains { $0.id.uuidString == stored } ? stored : ""
            },
            set: { preferences.shelfDefaultStash = $0 }
        )
    }

    private func chooseFolder() {
        guard let folder = StorageDialogs.chooseFolder(
            startingAt: StorageLocation.parent(stored: preferences.shelfLocation),
            message: L("Choose where to keep the stashes. They get a folder of their own there.")
        ) else { return }
        change(to: folder)
    }

    private func change(to parent: URL) {
        guard ShelfStashStore.directory(parentStored: StorageLocation.storedValue(for: parent)) != shelf.directory else { return }
        guard let useExisting = StorageDialogs.stashRelocation(destinationHasStashes: ShelfController.holdsStashes(below: parent)) else { return }
        if let failure = shelf.relocate(toParent: parent, useExisting: useExisting) { StorageDialogs.showFailure(failure) }
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
        case .ready: L("Set up; used from the System page")
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
