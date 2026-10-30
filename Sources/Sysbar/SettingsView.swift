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
    /// The add button's hover highlight, so its small symbol has a clear, comfortable target.
    @State private var addHovered = false
    /// Sidebar sections folded away by their chevron.
    @State private var collapsed: Set<SettingsSection> = []

    private var deviceIDs: [UUID] { preferences.devices.map(\.id) }

    /// The selection, with a removed device's page replaced by this Mac's.
    private var shown: SettingsPage { navigation.selection.resolved(deviceIDs: deviceIDs) }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $navigation.selection) {
                    // Headers are plain rows rather than `Section` headers: the native ones show
                    // their chevron only on hover and push the add button aside to make room.
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        sectionHeader(section)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                        if !collapsed.contains(section) {
                            ForEach(section.pages(deviceIDs: deviceIDs), id: \.self) { page in
                                sidebarRow(page).tag(page)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .motion(.easeInOut(duration: 0.18), value: collapsed)
                sidebarFooter
            }
            .background(SidebarMaterial().ignoresSafeArea())
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            // A soft cross-fade between pages.
            ZStack {
                page.id(shown).transition(.opacity)
            }
            .motion(.easeInOut(duration: 0.18), value: shown)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
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

    /// A section's title, with the add button (Devices only) and an always-visible chevron at fixed
    /// widths on the right, so nothing moves when the pointer passes over them.
    private func sectionHeader(_ section: SettingsSection) -> some View {
        let isExpanded = !collapsed.contains(section)
        return HStack(spacing: 6) {
            Button {
                toggle(section)
            } label: {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(isExpanded ? L("Expanded") : L("Collapsed"))
            .accessibilityAddTraits(.isHeader)
            if section == .devices {
                addMenu
            }
            Button {
                toggle(section)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.top, section == SettingsSection.allCases.first ? 0 : 8)
    }

    private func toggle(_ section: SettingsSection) {
        if collapsed.contains(section) {
            collapsed = collapsed.subtracting([section])
        } else {
            collapsed = collapsed.union([section])
        }
    }

    private var addMenu: some View {
        Menu {
            Button(L("Add manually…")) { adding = .blank }
            Button(L("Find on this network…")) { navigation.selection = .findDevices }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(addHovered ? 0.10 : 0.04)))
                .contentShape(Circle())
        }
        // The button style draws the label as SwiftUI does, in its secondary colour in both
        // appearances; `.borderlessButton` turned it into a fixed image, black in dark mode.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { addHovered = $0 }
        .motion(.easeOut(duration: 0.12), value: addHovered)
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

    /// Quit and the version, on one line at the bottom of the sidebar.
    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(L("Quit"), systemImage: "power")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Quits the app; the menu bar readout disappears too"))
                Spacer(minLength: 0)
                Text("v\(AppIdentity.shortVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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

/// The native sidebar material, drawn behind the header, list and footer. The window is made
/// non-opaque so the desktop shows through it, as it does in System Settings.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
