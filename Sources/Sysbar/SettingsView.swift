import AppKit
import SysbarCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, menuBar, popover, devices, preferences, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L("General")
        case .menuBar: L("Menu Bar")
        case .popover: L("Window")
        case .devices: L("Devices")
        case .preferences: L("Settings")
        case .about: L("About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: L("Summary of this Mac")
        case .menuBar: L("What appears in the menu bar and how it looks")
        case .popover: L("Cards and table shown in the popover")
        case .devices: L("Servers and Macs monitored over SSH")
        case .preferences: L("Sampling rate and startup")
        case .about: L("Version, data sources and limits")
        }
    }

    var symbol: String {
        switch self {
        case .general: "laptopcomputer"
        case .menuBar: "menubar.rectangle"
        case .popover: "square.grid.2x2"
        case .devices: "server.rack"
        case .preferences: "gearshape"
        case .about: "info.circle"
        }
    }
}

/// The page shown in the settings window. Held outside the view so the popover can open the window
/// straight onto a given page, such as the device list.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage = .general
}

/// The settings window: a grouped sidebar of pages on the left, the selected page on the right.
/// Quitting the app lives at the bottom of the sidebar rather than in the popover.
struct SettingsView: View {
    private static let sidebarGroups: [(title: String, pages: [SettingsPage])] = [
        (L("Monitoring"), [.general, .menuBar, .popover]),
        (L("Connections"), [.devices]),
        (L("App"), [.preferences, .about]),
    ]

    @ObservedObject var preferences: Preferences
    let updater: UpdateChecker
    let helper: HelperConnection
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(Self.sidebarGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.pages) { page in
                            // Same plain grey symbol as the page headers, instead of the
                            // sidebar's default accent-coloured icons.
                            Label {
                                Text(page.title)
                            } icon: {
                                Image(systemName: page.symbol)
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13, weight: .regular))
                                    .frame(width: 18)
                            }
                            .tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { quitButton }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            // A soft cross-fade between pages.
            ZStack {
                page.id(navigation.selection).transition(.opacity)
            }
            .motion(.easeInOut(duration: 0.18), value: navigation.selection)
        }
        .frame(minWidth: 740, minHeight: 500)
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
        switch navigation.selection {
        case .general: GeneralPage(preferences: preferences)
        case .menuBar: MenuBarPage(preferences: preferences)
        case .popover: PopoverPage(preferences: preferences)
        case .devices: DevicesPage(preferences: preferences)
        case .preferences: PreferencesPage(preferences: preferences, updater: updater, helper: helper)
        case .about: AboutPage(updater: updater, preferences: preferences)
        }
    }
}
