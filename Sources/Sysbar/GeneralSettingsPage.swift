import AppKit
import SysbarCore
import SwiftUI

/// Settings for the app itself: where it lives, its language, starting at login, updates, and going
/// back to the defaults. On the first run it opens with a welcome, as the first page of the window.
struct GeneralSettingsPage: View {
    @ObservedObject var preferences: Preferences
    let updater: UpdateChecker
    @State private var confirmsReset = false

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var language = AppLanguage.current
    private let launchLanguage = AppLanguage.current

    var body: some View {
        SettingsPageScaffold(page: .general, animating: AnyHashable(preferences.setupCompleted)) {
            if !preferences.setupCompleted { welcome }

            SettingsGroup(title: L("Location"), footer: Self.placementFooter) {
                SettingsRow(symbol: Self.hasNotch ? "macbook" : "menubar.rectangle", title: L("Show Sysbar in")) {
                    Picker(L("Show Sysbar in"), selection: $preferences.sysbarPlacement) {
                        Text(L("Menu bar")).tag(SysbarPlacement.menuBar)
                        Text(Self.hasNotch ? L("Notch") : L("Top of screen")).tag(SysbarPlacement.notch)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

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

            UpdateSettingsGroup(updater: updater)

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
                Text(L("Menu bar, notch, panel, sampling and update settings go back to their defaults."))
            }
        }
    }

    private var welcome: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: "hand.wave.fill", size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Welcome to Sysbar")).font(.headline)
                Text(L("Sysbar uses very few resources. Choose below whether it lives in the menu bar or around the notch, and what appears where on the pages at the left."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Get started")) { preferences.setupCompleted = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .settingsCard()
    }

    private static var hasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    private static var placementFooter: String {
        hasNotch
            ? L("Around the notch, the readouts sit either side of it and the panel opens when the pointer rests there. Sysbar then leaves the menu bar. On a display without a notch it shows as a small capsule at the top.")
            : L("At the top of the screen, Sysbar is a small capsule in the middle of the menu bar that opens when the pointer rests on it. Sysbar then leaves the menu bar.")
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
