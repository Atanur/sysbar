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
