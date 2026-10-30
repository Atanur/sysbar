import AppKit
import SysbarCore
import SwiftUI

/// Version and updates, links for help and feedback, privacy, data sources, and the limits of
/// what can be measured.
struct AboutPage: View {
    let updater: UpdateChecker
    @ObservedObject var preferences: Preferences
    @State private var copiedDiagnostics = false
    private let info = SystemInfoProbe.read()

    var body: some View {
        SettingsPageScaffold(page: .about) {
            header

            if let notes = BundledChangelog.current {
                SettingsGroup(title: L("What's new in %@", AppIdentity.shortVersion)) {
                    ReleaseNotesList(items: notes.items)
                        .font(.callout)
                        .padding(12)
                }
            }

            UpdateSettingsGroup(updater: updater)

            SettingsGroup(title: L("Help and feedback")) {
                linkRow("globe", L("Website"), "sysbar.atanur.dev", ProjectLinks.website)
                RowDivider()
                linkRow("chevron.left.forwardslash.chevron.right", L("Source code"), "GitHub", ProjectLinks.repository)
                RowDivider()
                linkRow(
                    "ladybug", L("Report a problem"), L("Opens a form on GitHub with your version and Mac filled in"),
                    ProjectLinks.bugReport(version: AppIdentity.versionText, system: info.osVersion, mac: macText)
                )
                RowDivider()
                linkRow("lightbulb", L("Suggest a feature"), L("Opens a form on GitHub"), ProjectLinks.featureRequest())
                RowDivider()
                linkRow("doc.text", L("Release notes"), L("Every release, on the website"), ProjectLinks.changelog)
                RowDivider()
                SettingsRow(
                    symbol: "doc.on.clipboard", title: L("Copy diagnostic info"),
                    subtitle: L("Version, Mac and settings for a problem report; no device addresses")
                ) {
                    Button(copiedDiagnostics ? L("Copied") : L("Copy"), action: copyDiagnostics)
                }
            }

            SettingsGroup(title: L("Privacy")) {
                infoRow("hand.raised", L("No analytics, no account"),
                        L("The only connections are the daily update check on GitHub and the SSH sessions you add"))
            }

            SettingsGroup(title: L("Data sources")) {
                infoRow("cpu", L("CPU, memory, disk and network"), L("macOS kernel counters"))
                RowDivider()
                infoRow("display", L("GPU usage"), L("Statistics from the graphics driver"))
                RowDivider()
                infoRow("bolt.fill", L("Power"), L("Total SMC power, energy counters and battery log"))
                RowDivider()
                infoRow("list.bullet", L("Per-app values"), L("Only processes from your own account"))
                RowDivider()
                infoRow("server.rack", L("Remote devices"), L("Using ssh, a key or ssh-agent on your system"))
            }

            SettingsGroup(title: L("Limits")) {
                infoRow("exclamationmark.triangle.fill", L("CPU and RAM power"),
                        L("On this macOS version it cannot be read without privileges, so it is not shown"))
                RowDivider()
                infoRow("exclamationmark.triangle.fill", L("Power per app"),
                        L("An estimate from the system, lower than the total"))
            }

            HStack(spacing: 4) {
                Text("© 2026 Atanur ·")
                Link(L("MIT License"), destination: ProjectLinks.license)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("Sysbar").font(.title.weight(.semibold))
            Button { copy("Sysbar \(AppIdentity.versionText)") } label: {
                Text(AppIdentity.versionLine).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Click to copy the version"))
            Text(L("A lightweight system monitor for the menu bar.")).padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .settingsCard()
    }

    private var macText: String {
        "\(info.modelName ?? info.modelIdentifier) (\(info.modelIdentifier)) · \(info.chip)"
    }

    private func copyDiagnostics() {
        copy(DiagnosticInfo.text(info: info, preferences: preferences, updater: updater))
        copiedDiagnostics = true
        announce(L("Copied"))
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedDiagnostics = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func linkRow(_ symbol: String, _ title: String, _ subtitle: String, _ url: URL) -> some View {
        SettingsRow(symbol: symbol, title: title, subtitle: subtitle) {
            Button { NSWorkspace.shared.open(url) } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help(url.absoluteString)
            .accessibilityLabel(L("Open %@", title))
        }
    }

    private func infoRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        SettingsRow(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// What the running copy of Sysbar is and where it came from.
enum AppIdentity {
    private static let caskrooms = ["/opt/homebrew/Caskroom/sysbar", "/usr/local/Caskroom/sysbar"]

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L("development")
    }

    /// "0.1.1 (6)": the version and the build number.
    static var versionText: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(shortVersion) (\($0))" } ?? shortVersion
    }

    /// "Version 0.1.1 (6) · Homebrew"
    static var versionLine: String {
        let version = L("Version %@", versionText)
        return isHomebrewInstall ? "\(version) · Homebrew" : version
    }

    static var isHomebrewInstall: Bool {
        caskrooms.contains { FileManager.default.fileExists(atPath: $0) }
    }
}

/// Plain text to paste into a problem report: the app, the Mac and the settings in use. Remote
/// devices are only counted; their names, addresses and users are left out.
@MainActor
enum DiagnosticInfo {
    static func text(info: SystemInfo, preferences: Preferences, updater: UpdateChecker) -> String {
        let interval = SamplingInterval.text(preferences.samplingInterval)
        let battery = preferences.batteryMenuBarThreshold == BatteryMenuBar.off
            ? "off" : "\(preferences.batteryMenuBarThreshold)%"
        let lines = [
            "Sysbar \(AppIdentity.versionText)\(AppIdentity.isHomebrewInstall ? " · Homebrew" : "")",
            "macOS: \(info.osVersion)",
            "Mac: \(info.modelName ?? info.modelIdentifier) (\(info.modelIdentifier)) · \(info.chip)",
            "Memory: \(Format.gigabytes(info.memoryBytes)) · cores: \(info.performanceCores)P + \(info.efficiencyCores)E",
            "Language: \(Bundle.main.preferredLocalizations.first ?? "?") · region: \(Locale.current.region?.identifier ?? "?")",
            "Refresh: \(interval) s · menu bar: \(names(preferences.menuBarMetrics)) · battery: \(battery)",
            "Cards: \(names(preferences.visibleCards)) · layout: \(preferences.cardLayout.rawValue)",
            "Apps table: \(preferences.showsApps ? "\(preferences.appRows) rows" : "off") · colored bars: \(preferences.coloredMenuBar)",
            "Remote devices: \(preferences.devices.count) · update check: \(updater.isAutomatic ? "on" : "off")",
        ]
        return lines.joined(separator: "\n")
    }

    private static func names(_ metrics: [MenuBarMetric]) -> String {
        metrics.isEmpty ? "none" : metrics.map(\.rawValue).joined(separator: ", ")
    }
}
