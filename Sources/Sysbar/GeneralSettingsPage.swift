import SysbarCore
import SwiftUI

/// Settings for the app itself: language, starting at login, and going back to the defaults.
struct GeneralSettingsPage: View {
    @ObservedObject var preferences: Preferences
    let updater: UpdateChecker
    @State private var confirmsReset = false

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var language = AppLanguage.current
    private let launchLanguage = AppLanguage.current

    var body: some View {
        SettingsPageScaffold(page: .general) {
            SettingsGroup(title: L("Language")) {
                SettingsRow(symbol: "globe", title: L("Language")) {
                    Picker(L("Language"), selection: Binding(get: { language }, set: { language = $0; AppLanguage.select($0) })) {
                        ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if language != launchLanguage {
                    RowDivider()
                    SettingsRow(symbol: "arrow.clockwise", title: L("Restart Sysbar to use the new language")) {
                        Button(L("Restart")) { AppLanguage.relaunch() }
                    }
                }
            }

            SettingsGroup(title: L("Startup"), footer: launchError) {
                SettingsRow(symbol: "power", title: L("Launch at login")) {
                    RowToggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                }
            }

            SettingsGroup(title: L("Reset")) {
                SettingsRow(
                    symbol: "arrow.counterclockwise", title: L("Reset all settings"),
                    subtitle: L("Language and launch at login are kept")
                ) {
                    Button(L("Reset…")) { confirmsReset = true }
                }
            }
            .confirmationDialog(L("Reset all settings?"), isPresented: $confirmsReset) {
                Button(L("Reset, keep remote devices")) { reset(keepingDevices: true) }
                Button(L("Reset and remove remote devices"), role: .destructive) { reset(keepingDevices: false) }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(L("Menu bar, window, sampling and update settings go back to their defaults."))
            }
        }
    }

    private func reset(keepingDevices: Bool) {
        preferences.resetToDefaults(keepingDevices: keepingDevices)
        updater.resetToDefaults()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = L("Could not change the setting: %@", error.localizedDescription)
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
