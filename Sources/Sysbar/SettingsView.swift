import AppKit
import SysbarCore
import SwiftUI

@MainActor
extension SettingsPage {
    /// Title of a fixed page. Device pages are titled with the device's name instead; see `SettingsView`.
    var title: String {
        switch self {
        case .thisMac: L("This Mac")
        case .device: L("Device")
        case .findDevices: L("Find devices")
        case .menuBarReadouts: L("Readouts")
        case .menuBarAppearance: L("Appearance")
        case .windowLayout: L("Layout")
        case .appsTable: L("Apps table")
        case .fans: L("Temperature and fans")
        case .keepAwake: L("Keep awake")
        case .general: L("General")
        case .about: L("About")
        }
    }

    var subtitle: String {
        switch self {
        case .thisMac, .device: ""
        case .findDevices: L("Macs on this network and machines in your Tailscale")
        case .menuBarReadouts: L("Which metrics appear in the menu bar, and in what order")
        case .menuBarAppearance: L("How the menu bar readout looks")
        case .windowLayout: L("How cards are arranged in the popover")
        case .appsTable: L("The busiest apps, under the cards in the popover")
        case .fans: L("Temperature readings and fan control in the popover")
        case .keepAwake: L("Keeps the Mac from sleeping, from the popover")
        case .general: L("Language, startup and reset")
        case .about: L("Version, data sources and limits")
        }
    }

    var symbol: String {
        switch self {
        case .thisMac: "laptopcomputer"
        case .device: "server.rack"
        case .findDevices: "antenna.radiowaves.left.and.right"
        case .menuBarReadouts: "menubar.rectangle"
        case .menuBarAppearance: "paintpalette"
        case .windowLayout: "square.grid.2x2"
        case .appsTable: "list.bullet.rectangle"
        case .fans: "fan"
        case .keepAwake: KeepAwakeController.hasLid ? "laptopcomputer" : "cup.and.saucer"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

extension SettingsSection {
    var title: String {
        switch self {
        case .devices: L("Devices")
        case .menuBar: L("Menu Bar")
        case .window: L("Window")
        case .tools: L("Tools")
        case .app: L("App")
        }
    }
}

/// The page shown in the settings window. Held outside the view so the menu and the popover can
/// open the window straight onto a given page.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage = .start
}

/// The settings window: a grouped sidebar of pages on the left, the selected page on the right.
/// The devices section lists this Mac and every remote device, and its add button adds another.
/// Quitting the app lives at the bottom of the sidebar rather than in the popover.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let updater: UpdateChecker
    let helper: HelperConnection
    @ObservedObject var navigation: SettingsNavigation
    @StateObject private var statuses = DeviceStatusStore()
    /// A new device in the editor, before it is saved.
    @State private var adding: RemoteDevice?

    private var deviceIDs: [UUID] { preferences.devices.map(\.id) }

    /// The selection, with a removed device's page replaced by this Mac's.
    private var shown: SettingsPage { navigation.selection.resolved(deviceIDs: deviceIDs) }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Section {
                        ForEach(section.pages(deviceIDs: deviceIDs), id: \.self) { page in
                            sidebarRow(page).tag(page)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { quitButton }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            // A soft cross-fade between pages.
            ZStack {
                page.id(shown).transition(.opacity)
            }
            .motion(.easeInOut(duration: 0.18), value: shown)
        }
        .frame(minWidth: 760, minHeight: 520)
        // A removed device's page gives way to this Mac's, in the sidebar too.
        .onChange(of: deviceIDs) { _, ids in navigation.selection = navigation.selection.resolved(deviceIDs: ids) }
        .sheet(item: $adding) { device in
            DeviceEditor(
                device: device,
                onSave: { saved in
                    preferences.saveDevice(saved)
                    adding = nil
                    navigation.selection = .device(saved.id)
                },
                onCancel: { adding = nil }
            )
        }
    }

    @ViewBuilder
    private func sectionHeader(_ section: SettingsSection) -> some View {
        if section == .devices {
            HStack {
                Text(section.title)
                Spacer()
                addMenu
            }
        } else {
            Text(section.title)
        }
    }

    private var addMenu: some View {
        Menu {
            Button(L("Add manually…")) { adding = .blank }
            Button(L("Find on this network…")) { navigation.selection = .findDevices }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Add device"))
        .accessibilityLabel(L("Add device"))
    }

    private func sidebarRow(_ page: SettingsPage) -> some View {
        // Same plain grey symbol as the page headers, instead of the sidebar's default
        // accent-coloured icons.
        Label {
            HStack {
                Text(title(of: page)).lineLimit(1)
                if case .device(let id) = page, let status = statuses.status(of: id) {
                    Spacer(minLength: 4)
                    StatusDot(status: status)
                }
            }
        } icon: {
            // Scaled down so the symbol stands no taller than the title beside it.
            Image(systemName: symbol(of: page))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .font(.body)
                .imageScale(.small)
                .frame(width: 16)
        }
    }

    private func symbol(of page: SettingsPage) -> String {
        if case .device(let id) = page, let device = preferences.device(id: id) { return device.icon.symbol }
        return page.symbol
    }

    private func title(of page: SettingsPage) -> String {
        switch page {
        case .thisMac: preferences.thisMacTitle
        case .device(let id): preferences.device(id: id)?.name ?? page.title
        default: page.title
        }
    }

    private var quitButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L("Quit Sysbar"), systemImage: "power")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .help(L("Quits the app; the menu bar readout disappears too"))
        }
    }

    @ViewBuilder
    private var page: some View {
        switch shown {
        case .thisMac: ThisMacPage(preferences: preferences)
        case .device(let id):
            if let device = preferences.device(id: id) {
                RemoteDevicePage(device: device, preferences: preferences, statuses: statuses)
            }
        case .findDevices: FindDevicesPage(preferences: preferences) { adding = $0 }
        case .menuBarReadouts: MenuBarReadoutsPage(preferences: preferences)
        case .menuBarAppearance: MenuBarAppearancePage(preferences: preferences)
        case .windowLayout: WindowLayoutPage(preferences: preferences) { navigation.selection = .thisMac }
        case .appsTable: AppsTablePage(preferences: preferences)
        case .fans: FansPage(preferences: preferences, helper: helper)
        case .keepAwake: KeepAwakePage(preferences: preferences, helper: helper)
        case .general: GeneralSettingsPage(preferences: preferences, updater: updater)
        case .about: AboutPage(updater: updater, preferences: preferences)
        }
    }
}
