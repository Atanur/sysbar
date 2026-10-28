import SysbarCore
import SwiftUI

/// One remote device's page: whether it answers right now, how it is reached, which cards its tab
/// shows, how it is sampled, and removing it. The device is checked each time the page opens.
struct RemoteDevicePage: View {
    let device: RemoteDevice
    @ObservedObject var preferences: Preferences
    @ObservedObject var statuses: DeviceStatusStore
    @State private var editing = false
    @State private var confirmsRemoval = false

    var body: some View {
        SettingsPageScaffold(
            symbol: device.icon.symbol, title: device.name, subtitle: device.address,
            animating: AnyHashable(statuses.status(of: device.id))
        ) {
            Button { editing = true } label: {
                Label(L("Edit"), systemImage: "pencil")
            }
            .help(L("Change its name and how it is reached"))
        } content: {
            if !device.problems.isEmpty { problemsGroup }
            statusGroup
            connectionGroup
            cardsGroup
            samplingGroup
            removeGroup
        }
        .onAppear { statuses.check(device) }
        .sheet(isPresented: $editing) {
            DeviceEditor(
                device: device,
                onSave: { saved in
                    let previous = device
                    preferences.saveDevice(saved)
                    editing = false
                    guard saved.connectsDifferently(from: previous) else { return }
                    // A kept-warm connection belongs to the old settings; end it first, so the check
                    // connects with the new ones.
                    Task {
                        await SSHRunner().closeConnection(previous)
                        statuses.check(saved)
                    }
                },
                onCancel: { editing = false }
            )
        }
    }

    // MARK: Groups

    /// Stored settings that no longer pass validation cannot be saved, so changes here would not
    /// stick until the connection is fixed in the editor.
    private var problemsGroup: some View {
        SettingsGroup(footer: L("Fix this with Edit; until then changes on this page are not saved.")) {
            ForEach(device.problems, id: \.self) { problem in
                SettingsRow(symbol: "exclamationmark.triangle", title: DeviceEditor.message(for: problem)) {}
            }
        }
    }

    private var statusGroup: some View {
        SettingsGroup(title: L("Status")) {
            switch statuses.status(of: device.id) ?? .checking {
            case .checking:
                SettingsRow(symbol: "antenna.radiowaves.left.and.right", title: L("Checking…")) {
                    ProgressView().controlSize(.small)
                }
            case .connected(let text):
                statusRow(symbol: "checkmark.circle", text: text, color: Color(nsColor: .systemGreen))
            case .failed(let text):
                statusRow(symbol: "exclamationmark.triangle", text: text, color: Color(nsColor: .systemRed))
            }
        }
    }

    private func statusRow(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 12)
            Button(L("Check again")) { statuses.check(device) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }

    private var connectionGroup: some View {
        SettingsGroup(
            title: L("Connection"),
            footer: L("Authentication uses an ssh key or ssh-agent; passwords are not supported. You must have connected to the server from Terminal at least once.")
        ) {
            infoRow("server.rack", L("Server"), device.host)
            RowDivider()
            infoRow("person", L("User"), device.user.isEmpty ? L("Same as on this Mac") : device.user)
            RowDivider()
            infoRow("number", L("Port"), device.port.map(String.init) ?? "22")
            RowDivider()
            infoRow("key", L("Key file"), device.identityFile.isEmpty ? L("ssh-agent or the default key") : device.identityFile)
        }
    }

    private var cardsGroup: some View {
        SettingsGroup(
            title: L("Cards"),
            footer: L("Disk and GPU cards appear only if the server reports that data. The process table is always shown.")
        ) {
            ForEach(Array(RemoteCard.allCases.enumerated()), id: \.element) { index, card in
                if index > 0 { RowDivider() }
                SettingsRow(symbol: card.symbol, title: card.displayName) {
                    RowToggle(isOn: Binding(
                        get: { device.cards.contains(card) },
                        set: { _ in save(cards: OrderedSelection.toggling(card, in: device.cards, minimum: 0)) }
                    ))
                }
            }
        }
    }

    private var samplingGroup: some View {
        SettingsGroup(
            title: L("Sampling"),
            footer: L("A device is sampled while its tab is shown, and for its keep-monitoring time after the popover closes.")
        ) {
            SettingsRow(symbol: "timer", title: L("Refresh rate")) {
                IntervalSlider(
                    value: Binding(get: { device.interval }, set: { save(interval: $0) }),
                    range: SamplingInterval.remoteRange,
                    step: 1,
                    normalize: SamplingInterval.normalizedRemote,
                    debounce: .milliseconds(500)
                )
            }
            RowDivider()
            SettingsRow(symbol: "clock.arrow.circlepath", title: L("Keep monitoring after closing")) {
                Picker("", selection: Binding(get: { device.keepMonitoring }, set: { save(keepMonitoring: $0) })) {
                    ForEach(KeepMonitoring.choices, id: \.self) { Text(Self.title(of: $0)).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var removeGroup: some View {
        SettingsGroup {
            SettingsRow(
                symbol: "trash", title: L("Remove device"),
                subtitle: L("Only Sysbar forgets it; nothing changes on the device")
            ) {
                Button(L("Remove…"), role: .destructive) { confirmsRemoval = true }
            }
        }
        .confirmationDialog(L("Remove %@?", device.name), isPresented: $confirmsRemoval) {
            Button(L("Remove"), role: .destructive) {
                let removed = device
                statuses.forget(removed.id)
                preferences.deleteDevice(id: removed.id)
                Task { await SSHRunner().closeConnection(removed) }
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    private func infoRow(_ symbol: String, _ title: String, _ value: String) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    // MARK: Changes

    /// Cards and sampling take effect as they are changed; only the connection needs the editor.
    /// Starts from the stored device, not the one this view was drawn with, so a late write (the
    /// slider's, after its pause) does not undo a change made in the meantime.
    private func save(
        cards: [RemoteCard]? = nil, interval: TimeInterval? = nil, keepMonitoring: KeepMonitoring? = nil
    ) {
        guard let current = preferences.device(id: device.id) else { return }
        preferences.saveDevice(RemoteDevice(
            id: current.id, name: current.name, host: current.host, user: current.user, port: current.port,
            identityFile: current.identityFile, cards: cards ?? current.cards,
            interval: interval ?? current.interval, keepMonitoring: keepMonitoring ?? current.keepMonitoring,
            icon: current.icon
        ))
    }

    private static func title(of choice: KeepMonitoring) -> String {
        switch choice {
        case .off: L("Off")
        case .always: L("Always")
        case .minutes(let minutes) where minutes >= 60: L("%@h", "\(minutes / 60)")
        case .minutes(let minutes): L("%@m", "\(minutes)")
        }
    }
}

extension RemoteCard {
    /// Name used on the device's page.
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

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .load: "gauge.with.dots.needle.33percent"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .gpu: "display"
        }
    }
}
