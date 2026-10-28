import AppKit
import SysbarCore
import SwiftUI

/// The list of remote machines, with add, edit and delete.
struct DevicesPage: View {
    @ObservedObject var preferences: Preferences
    @State private var editing: RemoteDevice?
    @State private var renamingThisMac = false

    /// "MacBook Pro (14-inch, 2024)", read once.
    private static let model: String = {
        let info = SystemInfoProbe.read()
        return info.modelName ?? info.modelIdentifier
    }()

    var body: some View {
        SettingsPageScaffold(page: .devices, animating: AnyHashable(preferences.devices.map(\.id))) {
            SettingsGroup(footer: L("Its name is shown on its tab in the popover.")) {
                thisMacRow
            }
            if preferences.devices.isEmpty {
                emptyState
            } else {
                SettingsGroup(
                    title: L("Remote devices"),
                    footer: L("A device is sampled while its tab is shown, and for its keep-monitoring time after the popover closes. Authentication uses an ssh key or ssh-agent; passwords are not supported. You must have connected to the server from Terminal at least once.")
                ) {
                    ForEach(Array(preferences.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { RowDivider() }
                        deviceRow(device)
                    }
                }
                HStack {
                    Spacer()
                    addButton
                }
            }
            DiscoveredDevicesView(preferences: preferences) { editing = $0 }
            DeviceSetupGuideView()
        }
        .sheet(item: $editing) { device in
            DeviceEditor(
                device: device,
                onSave: { saved in
                    // A kept-warm connection may belong to the old settings; end it so the next use
                    // connects with the new ones.
                    if let previous = preferences.device(id: saved.id) { closeConnection(of: previous) }
                    preferences.saveDevice(saved)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
        .sheet(isPresented: $renamingThisMac) {
            ThisMacNameEditor(
                name: preferences.thisMacName,
                onSave: { name in
                    preferences.thisMacName = name
                    renamingThisMac = false
                },
                onCancel: { renamingThisMac = false }
            )
        }
    }

    /// This Mac, always first: it can be renamed but not removed.
    private var thisMacRow: some View {
        let renamed = preferences.thisMacTitle != L("This Mac")
        return SettingsRow(
            symbol: "laptopcomputer", title: preferences.thisMacTitle,
            subtitle: renamed ? "\(L("This Mac")) · \(Self.model)" : Self.model
        ) {
            Button { renamingThisMac = true } label: {
                Image(systemName: "pencil").frame(width: 18, height: 18)
            }
            .help(L("Rename"))
            .accessibilityLabel(L("Rename %@", preferences.thisMacTitle))
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func deviceRow(_ device: RemoteDevice) -> some View {
        SettingsRow(
            symbol: "server.rack", title: device.name,
            subtitle: L("%1$@ · %2$@ cards", device.address, "\(device.cards.count)")
        ) {
            HStack(spacing: 8) {
                Button { editing = device } label: {
                    Image(systemName: "pencil").frame(width: 18, height: 18)
                }
                .help(L("Edit"))
                .accessibilityLabel(L("Edit"))
                Button {
                    closeConnection(of: device)
                    preferences.deleteDevice(id: device.id)
                } label: {
                    Image(systemName: "trash").frame(width: 18, height: 18)
                }
                .help(L("Delete"))
                .accessibilityLabel(L("Delete %@", device.name))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var addButton: some View {
        Button {
            editing = RemoteDevice(name: "", host: "", user: "", port: nil, identityFile: "")
        } label: {
            Label(L("Add device"), systemImage: "plus")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            IconTile(symbol: "server.rack", size: 52)
            Text(L("No devices yet")).font(.headline)
            Text(L("Add Linux servers and Macs with SSH turned on, then watch their live usage from the tabs at the top of the popover."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            addButton
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .settingsCard()
    }

    private func closeConnection(of device: RemoteDevice) {
        Task { await SSHRunner().closeConnection(device) }
    }
}

/// Renames this Mac. An empty name goes back to "This Mac".
struct ThisMacNameEditor: View {
    @State var name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(L("Name"), text: $name, prompt: Text(L("This Mac")))
                } footer: {
                    Text(L("Shown on its tab in the popover. Leave it empty to use This Mac."))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Save")) { onSave(LocalDeviceName.normalized(name)) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 400)
    }
}

/// Add or edit one device, with a button that tries the connection before saving.
struct DeviceEditor: View {
    private enum TestState: Equatable {
        case idle, running, success(String), failure(String)
    }

    let original: RemoteDevice
    let onSave: (RemoteDevice) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var host: String
    @State private var user: String
    @State private var portText: String
    @State private var identity: String
    @State private var cards: [RemoteCard]
    @State private var interval: TimeInterval
    @State private var keepMonitoring: KeepMonitoring
    @State private var test = TestState.idle

    init(device: RemoteDevice, onSave: @escaping (RemoteDevice) -> Void, onCancel: @escaping () -> Void) {
        original = device
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: device.name)
        _host = State(initialValue: device.host)
        _user = State(initialValue: device.user)
        _portText = State(initialValue: device.port.map(String.init) ?? "")
        _identity = State(initialValue: device.identityFile)
        _cards = State(initialValue: device.cards)
        _interval = State(initialValue: device.interval)
        _keepMonitoring = State(initialValue: device.keepMonitoring)
    }

    private var trimmedPort: String { portText.trimmingCharacters(in: .whitespaces) }

    private var draft: RemoteDevice {
        RemoteDevice(
            id: original.id, name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces), user: user.trimmingCharacters(in: .whitespaces),
            port: Int(trimmedPort), identityFile: identity.trimmingCharacters(in: .whitespaces), cards: cards,
            interval: interval, keepMonitoring: keepMonitoring
        )
    }

    /// A port that is typed but is not a number is a problem even though `draft` reads it as unset.
    private var problems: [RemoteDevice.Problem] {
        var found = draft.problems
        if !trimmedPort.isEmpty, Int(trimmedPort) == nil, !found.contains(.invalidPort) { found.append(.invalidPort) }
        return found
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(L("Name"), text: $name, prompt: Text(L("e.g. My server")))
                    TextField(L("Server"), text: $host, prompt: Text(L("e.g. vps.example.com or an ssh alias")))
                    TextField(L("User"), text: $user, prompt: Text(L("Optional")))
                    TextField(L("Port"), text: $portText, prompt: Text(L("Default 22")))
                    HStack {
                        TextField(L("Key file"), text: $identity, prompt: Text(L("Optional, e.g. ~/.ssh/id_ed25519")))
                        Button(L("Choose…"), action: pickIdentity)
                    }
                } footer: {
                    ForEach(problems, id: \.self) { problem in
                        Text(Self.message(for: problem)).foregroundStyle(LoadLevel.high.color)
                    }
                }
                Section {
                    ForEach(RemoteCard.allCases, id: \.self) { card in
                        Toggle(card.displayName, isOn: Binding(
                            get: { cards.contains(card) },
                            set: { _ in cards = OrderedSelection.toggling(card, in: cards, minimum: 0) }
                        ))
                    }
                } header: {
                    Text(L("Cards shown for this device"))
                } footer: {
                    Text(L("Disk and GPU cards appear only if the server reports that data. The process table is always shown."))
                }
                Section(L("Sampling")) {
                    LabeledContent(L("Refresh rate")) {
                        IntervalSlider(
                            value: $interval,
                            range: SamplingInterval.remoteRange,
                            step: 1,
                            normalize: SamplingInterval.normalizedRemote
                        )
                    }
                    Picker(L("Keep monitoring after closing"), selection: $keepMonitoring) {
                        ForEach(KeepMonitoring.choices, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                    }
                }
                Section {
                    HStack {
                        Button(L("Test connection"), action: runTest)
                            .disabled(!problems.isEmpty || test == .running)
                        testResult
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Save")) { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!problems.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480)
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .success(let text):
            Label(text, systemImage: "checkmark.circle").foregroundStyle(LoadLevel.low.color)
        case .failure(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(LoadLevel.high.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runTest() {
        let device = draft
        test = .running
        Task {
            let runner = SSHRunner()
            // A connection kept warm from earlier would be reused without authenticating, which
            // would hide a wrong key. Test from a clean state, and leave nothing open afterwards.
            await runner.closeConnection(device)
            let result = await runner.run(device)
            await runner.closeConnection(device)
            switch result {
            case .failure(let error):
                test = .failure(error.message)
            case .success(let output):
                test = RemoteMetricsParser.parse(output).map { .success(Self.summary(of: $0)) }
                    ?? .failure(L("The server sent an unexpected response."))
            }
        }
    }

    private static func summary(of sample: RemoteRawSample) -> String {
        switch sample.os {
        case .linux, .macOS:
            let system = sample.os == .macOS ? "macOS" : "Linux"
            let connected = L("Connected: %1$@ · %2$@ cores", system, "\(sample.cores)")
            guard let total = sample.memoryTotalBytes else { return connected }
            return "\(connected) · \(Format.gigabytes(total))"
        case .other:
            return L("Connected, but this system is not supported. Only Linux and macOS can be monitored.")
        }
    }

    private func pickIdentity() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            identity = url.path
        }
    }

    private static func title(of choice: KeepMonitoring) -> String {
        switch choice {
        case .off: L("Off")
        case .always: L("Always")
        case .minutes(let minutes) where minutes >= 60: L("%@h", "\(minutes / 60)")
        case .minutes(let minutes): L("%@m", "\(minutes)")
        }
    }

    private static func message(for problem: RemoteDevice.Problem) -> String {
        switch problem {
        case .emptyName: L("Enter a name.")
        case .invalidHost: L("Invalid server name. Letters, digits, dots, hyphens and colons are allowed, and it cannot start with a hyphen.")
        case .invalidUser: L("Invalid user name.")
        case .invalidPort: L("Port must be a number between 1 and 65535.")
        case .invalidIdentityFile: L("Key file must be a full path, starting with / or ~/.")
        }
    }
}

extension RemoteCard {
    /// Name used in the device editor.
    var displayName: String {
        switch self {
        case .cpu: L("Processor (CPU)")
        case .memory: L("Memory (RAM)")
        case .load: L("Load average")
        case .network: L("Network")
        case .disk: L("Disk")
        case .gpu: L("Graphics (GPU)")
        }
    }
}
