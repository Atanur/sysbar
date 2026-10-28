import SysbarCore
import SwiftUI

/// Devices Sysbar found on this network and in Tailscale, each with a button that walks through
/// connecting it. Shown under the device list in Settings › Devices.
struct DiscoveredDevicesView: View {
    @ObservedObject var preferences: Preferences
    /// Called with the device to open in the editor, prefilled from what was found.
    let onAdd: (RemoteDevice) -> Void

    @StateObject private var finder = DeviceFinder()
    @State private var connecting: DeviceDiscovery.Found?
    @State private var pending: RemoteDevice?

    private var found: [DeviceDiscovery.Found] {
        DeviceDiscovery.merge(
            local: finder.local, tailscale: finder.tailscale, thisMac: finder.thisMac,
            added: preferences.devices.map(\.host)
        )
    }

    var body: some View {
        let all = found
        let shown = all.filter { !preferences.hiddenSuggestions.contains($0.id) }
        let hiddenCount = all.count - shown.count
        SettingsGroup(
            title: L("Found on your network"),
            footer: L("Macs with Remote Login on in this network, and your Macs and Linux machines in Tailscale. Sysbar only reads these lists; it connects to nothing until you add a device.")
        ) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, device in
                if index > 0 { RowDivider() }
                row(device)
            }
            if !shown.isEmpty, !preferences.searchesLocalNetwork || hiddenCount > 0 { RowDivider() }
            if !preferences.searchesLocalNetwork {
                searchRow
            } else if shown.isEmpty, hiddenCount == 0 {
                SettingsRow(symbol: "antenna.radiowaves.left.and.right", title: L("No other devices found yet.")) {
                    if finder.isBrowsing { ProgressView().controlSize(.small) }
                }
            }
            if hiddenCount > 0 {
                SettingsRow(symbol: "eye.slash", title: L("%@ hidden", "\(hiddenCount)")) {
                    Button(L("Show")) { preferences.hiddenSuggestions = [] }
                }
            }
        }
        .onAppear {
            finder.refreshTailscale()
            if preferences.searchesLocalNetwork { finder.startBrowsing() }
        }
        .onDisappear { finder.stopBrowsing() }
        .sheet(item: $connecting, onDismiss: {
            // The editor opens once this sheet is gone; macOS shows one sheet at a time.
            if let pending { onAdd(pending) }
            pending = nil
        }) { device in
            ConnectFoundDeviceSheet(
                found: device,
                onAdd: { pending = $0; connecting = nil },
                onCancel: { connecting = nil }
            )
        }
    }

    private func row(_ device: DeviceDiscovery.Found) -> some View {
        SettingsRow(symbol: Self.symbol(of: device), title: device.name, subtitle: Self.addresses(of: device)) {
            HStack(spacing: 8) {
                Button(L("Add…")) { connecting = device }
                Button { preferences.hiddenSuggestions = preferences.hiddenSuggestions + [device.id] } label: {
                    Image(systemName: "eye.slash").frame(width: 18, height: 18)
                }
                .help(L("Hide"))
                .accessibilityLabel(L("Hide %@", device.name))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .opacity(device.isReachable ? 1 : 0.6)
    }

    private var searchRow: some View {
        SettingsRow(
            symbol: "antenna.radiowaves.left.and.right", title: L("Look for Macs on this network"),
            subtitle: L("macOS asks once to allow Sysbar on the local network.")
        ) {
            Button(L("Search")) {
                preferences.searchesLocalNetwork = true
                finder.startBrowsing()
            }
            .buttonStyle(.bordered)
        }
    }

    private static func symbol(of device: DeviceDiscovery.Found) -> String {
        device.system == .linux ? "server.rack" : "laptopcomputer"
    }

    /// "Tailscale 100.64.0.3 · Air.local", with "offline" when Tailscale says so.
    private static func addresses(of device: DeviceDiscovery.Found) -> String {
        let tailscale = device.tailscale.map { peer in
            "Tailscale \(peer.address)" + (peer.isOnline ? "" : " (\(L("offline")))")
        }
        return [tailscale, device.localHost].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Connecting a found device: pick its address and user name, run the few commands shown with
/// them filled in, then go on to the device editor, where the connection can be tested.
struct ConnectFoundDeviceSheet: View {
    let found: DeviceDiscovery.Found
    let onAdd: (RemoteDevice) -> Void
    let onCancel: () -> Void

    @State private var host: String
    @State private var user = NSUserName()
    @State private var system: DeviceSetupGuide.System

    init(found: DeviceDiscovery.Found, onAdd: @escaping (RemoteDevice) -> Void, onCancel: @escaping () -> Void) {
        self.found = found
        self.onAdd = onAdd
        self.onCancel = onCancel
        _host = State(initialValue: found.hosts.first ?? "")
        // Bonjour does not tell the system; Macs announce Remote Login on their own, most Linux
        // servers do not, so a Mac is the likely one and the picker below can change it.
        _system = State(initialValue: found.system ?? .mac)
    }

    private var trimmedUser: String { user.trimmingCharacters(in: .whitespaces) }

    private var destination: String { trimmedUser.isEmpty ? host : "\(trimmedUser)@\(host)" }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if found.hosts.count > 1 {
                        Picker(L("Address"), selection: $host) {
                            ForEach(found.hosts, id: \.self) { Text(verbatim: Self.label(of: $0, in: found)).tag($0) }
                        }
                    } else {
                        LabeledContent(L("Address")) { Text(verbatim: host).textSelection(.enabled) }
                    }
                    TextField(L("User"), text: $user, prompt: Text(L("Your user name on that device")))
                    if found.system == nil {
                        Picker(L("System"), selection: $system) {
                            Text(verbatim: "Mac").tag(DeviceSetupGuide.System.mac)
                            Text(verbatim: "Linux").tag(DeviceSetupGuide.System.linux)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text(found.name)
                } footer: {
                    if found.hosts.count > 1 {
                        Text(L("The Tailscale address also works away from this network."))
                    }
                }
                Section(L("Run once in Terminal")) {
                    GuideSteps(steps: DeviceSetupGuide.steps(
                        for: system, existingKey: DeviceSetupGuideView.existingKey(),
                        destination: destination, sshIsOn: found.localHost != nil
                    ))
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Add device")) {
                    onAdd(RemoteDevice(name: found.name, host: host, user: trimmedUser, port: nil, identityFile: ""))
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    /// "100.64.0.3 · Tailscale" or "Air.local · Local network".
    private static func label(of host: String, in found: DeviceDiscovery.Found) -> String {
        host == found.tailscale?.address ? "\(host) · Tailscale" : "\(host) · \(L("Local network"))"
    }
}
