import AppKit
import ServiceManagement
import SysbarCore

/// The app's side of fan control: registers the privileged helper once (macOS asks the user to
/// approve it in System Settings), then sends it "manual at this speed" or "automatic".
///
/// Manual mode lasts for this run of Sysbar only. It ends, and macOS takes the fans back, when
/// Sysbar quits or crashes (the helper sees the connection close), when the Mac sleeps, or when
/// the user switches back to automatic.
@MainActor
final class FanController: ObservableObject {
    enum Mode: Equatable {
        case automatic
        /// 0 is each fan's minimum speed, 1 its maximum.
        case manual(Double)

        var isManual: Bool { if case .manual = self { true } else { false } }
    }

    enum HelperState: Equatable {
        /// The helper is registered and approved.
        case ready
        /// Registered, waiting for the user to allow it in System Settings → Login Items.
        case needsApproval
        case notInstalled
        /// This copy cannot use a helper, e.g. a development build without a Developer ID.
        case unavailable
    }

    /// Only Macs with fans offer fan control. Read once: the SMC key scan is slow.
    static let macHasFans = !ThermalProbe().read().fans.isEmpty

    /// The version for which the user was last asked to set up the helper.
    private static let askedVersionKey = "fanHelperAskedVersion"

    /// A request the helper has not answered by then counts as failed.
    private static let replyTimeout: Duration = .seconds(5)

    /// Slider changes are sent once it has rested this long.
    private static let sendDelay: Duration = .milliseconds(250)

    @Published private(set) var mode: Mode = .automatic
    @Published private(set) var helperState: HelperState = .notInstalled
    @Published private(set) var lastError: String?
    /// The helper is registered but did not answer; registering it again usually clears it.
    @Published private(set) var isUnresponsive = false

    private let service = SMAppService.daemon(plistName: FanControlLimits.helperPlist)
    private let team = FanControlLimits.signingTeam()
    private var connection: NSXPCConnection?
    private var pendingSend: Task<Void, Never>?
    /// Renews manual mode before the helper's lease runs out.
    private var renewal: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init() {
        refreshHelperState()
        // The helper hands the fans back before sleep; show that after waking.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renewal?.cancel()
                self?.mode = .automatic
            }
        }
    }

    func refreshHelperState() {
        guard team != nil else {
            helperState = .unavailable
            return
        }
        helperState = switch service.status {
        case .enabled: .ready
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .notInstalled
        }
    }

    /// Registers the helper; macOS then asks for approval in System Settings, which is opened.
    func install() {
        lastError = nil
        do {
            try service.register()
        } catch {
            lastError = L("Could not set up fan control: %@", error.localizedDescription)
        }
        refreshHelperState()
        if helperState == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Asks once per version, on a Mac with fans, when the helper is not set up or macOS wants it
    /// approved again (as can happen after an update). "Not now" is remembered until the next version.
    func askForApprovalIfNeeded(defaults: UserDefaults = .standard) {
        refreshHelperState()
        let version = AppIdentity.versionText
        guard
            Self.macHasFans, helperState == .notInstalled || helperState == .needsApproval,
            defaults.string(forKey: Self.askedVersionKey) != version
        else { return }
        defaults.set(version, forKey: Self.askedVersionKey)

        let alert = NSAlert()
        alert.messageText = L("Let Sysbar control the fans?")
        alert.informativeText = helperState == .needsApproval
            ? L("macOS needs you to allow Sysbar's fan helper again in System Settings → General → Login Items.")
            : L("Sysbar can run the fans faster or slower when you choose to. This needs a small helper that macOS asks you to approve once. You can also do this later in Settings.")
        alert.addButton(withTitle: helperState == .needsApproval ? L("Open System Settings") : L("Set up…"))
        alert.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if helperState == .needsApproval { openApprovalSettings() } else { install() }
    }

    /// Removes and registers the helper again, for when macOS lists it but will not start it.
    func reinstall() async {
        connection?.invalidate()
        connection = nil
        try? await service.unregister()
        isUnresponsive = false
        install()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func uninstall() async {
        await sendAutomatic()
        connection?.invalidate()
        connection = nil
        do {
            try await service.unregister()
        } catch {
            lastError = L("Could not remove fan control: %@", error.localizedDescription)
        }
        refreshHelperState()
    }

    /// Sets every fan to `fraction` of its range; sent once the slider settles.
    func setManual(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        mode = .manual(clamped)
        pendingSend?.cancel()
        pendingSend = Task { [weak self] in
            try? await Task.sleep(for: Self.sendDelay)
            guard !Task.isCancelled else { return }
            await self?.sendManual(clamped)
            self?.startRenewal()
        }
    }

    func setAutomatic() {
        pendingSend?.cancel()
        renewal?.cancel()
        mode = .automatic
        Task { await sendAutomatic() }
    }

    private func sendManual(_ fraction: Double) async {
        await send { fans, reply in fans.setManual(fraction: fraction, reply: reply) }
    }

    /// While manual, the speed is sent again well inside the helper's lease; if Sysbar hangs,
    /// the renewals stop and the helper hands the fans back by itself.
    private func startRenewal() {
        renewal?.cancel()
        guard mode.isManual else { return }
        renewal = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(FanControlLimits.renewSeconds))
                guard !Task.isCancelled, let self, case .manual(let fraction) = self.mode else { return }
                await self.sendManual(fraction)
            }
        }
    }

    private func sendAutomatic() async {
        guard connection != nil else { return }
        await send { fans, reply in fans.setAutomatic(reply: reply) }
    }

    /// Runs one request on the helper. A failure is shown and the mode falls back to automatic;
    /// the helper itself hands every fan back when a manual request fails part way.
    private func send(_ request: @escaping (FanControlProtocol, @escaping (String?) -> Void) -> Void) async {
        refreshHelperState()
        guard helperState == .ready, let connection = openConnection() else {
            mode = .automatic
            return
        }
        let timeout = L("The fan helper did not answer.")
        let failure: String? = await withCheckedContinuation { continuation in
            let once = ReplyOnce(continuation)
            Task {
                try? await Task.sleep(for: Self.replyTimeout)
                once.resume(timeout)
            }
            let remote = connection.remoteObjectProxyWithErrorHandler { error in once.resume(error.localizedDescription) }
            guard let fans = remote as? FanControlProtocol else {
                once.resume(L("The fan helper did not answer."))
                return
            }
            request(fans) { once.resume($0) }
        }
        lastError = failure
        isUnresponsive = failure == timeout
        if failure != nil {
            renewal?.cancel()
            mode = .automatic
        }
    }

    private func openConnection() -> NSXPCConnection? {
        if let connection { return connection }
        guard let team else { return nil }
        let connection = NSXPCConnection(machServiceName: FanControlLimits.helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
        connection.setCodeSigningRequirement(
            FanControlLimits.requirement(identifier: FanControlLimits.helperLabel, team: team)
        )
        // The helper returns the fans to automatic when the connection ends.
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.renewal?.cancel()
                self?.mode = .automatic
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// XPC may call both the reply and the error handler; the continuation must resume once.
private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
