import AppKit
import SysbarCore
import SwiftUI

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

/// Add a device, or change how one is reached, with a button that tries the connection before
/// saving. Its cards and sampling are set on the device's own page.
struct DeviceEditor: View {
    let original: RemoteDevice
    let onSave: (RemoteDevice) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var host: String
    @State private var user: String
    @State private var portText: String
    @State private var identity: String
    @State private var icon: DeviceIcon
    /// The connection test's result; nil until it is run.
    @State private var test: DeviceStatus?

    init(device: RemoteDevice, onSave: @escaping (RemoteDevice) -> Void, onCancel: @escaping () -> Void) {
        original = device
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: device.name)
        _host = State(initialValue: device.host)
        _user = State(initialValue: device.user)
        _portText = State(initialValue: device.port.map(String.init) ?? "")
        _identity = State(initialValue: device.identityFile)
        _icon = State(initialValue: device.icon)
    }

    private var trimmedPort: String { portText.trimmingCharacters(in: .whitespaces) }

    private var draft: RemoteDevice {
        RemoteDevice(
            id: original.id, name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces), user: user.trimmingCharacters(in: .whitespaces),
            port: Int(trimmedPort), identityFile: identity.trimmingCharacters(in: .whitespaces),
            cards: original.cards, interval: original.interval, keepMonitoring: original.keepMonitoring,
            icon: icon
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
                    LabeledContent(L("Icon")) { DeviceIconPicker(selection: $icon) }
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
                    HStack {
                        Button(L("Test connection"), action: runTest)
                            .disabled(!problems.isEmpty || test == .checking)
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
        case nil:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .connected(let text):
            Label(text, systemImage: "checkmark.circle").foregroundStyle(LoadLevel.low.color)
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .foregroundStyle(LoadLevel.high.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runTest() {
        let device = draft
        test = .checking
        Task {
            let runner = SSHRunner()
            // A connection kept warm from earlier would be reused without authenticating, which
            // would hide a wrong key. Test from a clean state, and leave nothing open afterwards.
            await runner.closeConnection(device)
            let result = await runner.run(device)
            await runner.closeConnection(device)
            let status = DeviceStatus.from(result)
            test = status
            if let message = status.message { announce(message) }
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

    static func message(for problem: RemoteDevice.Problem) -> String {
        switch problem {
        case .emptyName: L("Enter a name.")
        case .invalidHost: L("Invalid server name. Letters, digits, dots, hyphens and colons are allowed, and it cannot start with a hyphen.")
        case .invalidUser: L("Invalid user name.")
        case .invalidPort: L("Port must be a number between 1 and 65535.")
        case .invalidIdentityFile: L("Key file must be a full path, starting with / or ~/.")
        }
    }
}

extension RemoteDevice {
    /// An empty device for the editor to fill in, with a new id each time.
    static var blank: RemoteDevice {
        RemoteDevice(name: "", host: "", user: "", port: nil, identityFile: "")
    }
}

/// A row of the device icons; the chosen one is filled with the accent colour.
struct DeviceIconPicker: View {
    @Binding var selection: DeviceIcon

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DeviceIcon.allCases, id: \.self) { icon in
                Button { selection = icon } label: {
                    Image(systemName: icon.symbol)
                        .font(.system(size: 14))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(icon == selection ? Color(nsColor: .alternateSelectedControlTextColor) : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(icon == selection ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(icon.title)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(icon == selection ? .isSelected : [])
            }
        }
    }
}

extension DeviceIcon {
    var title: String {
        switch self {
        case .server: L("Server")
        case .cloud: L("Cloud server")
        case .nas: "NAS"
        case .pc: "PC"
        case .laptop: L("Laptop")
        case .iMac: "iMac"
        case .macMini: "Mac mini"
        case .macStudio: "Mac Studio"
        }
    }
}
