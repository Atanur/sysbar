import AppKit
import Combine
import ServiceManagement
import SysbarCore

/// The app's one link to its privileged helper: registers it once (macOS asks the user to approve
/// it in System Settings), keeps the connection and runs requests on it. Fan control and keeping
/// the Mac awake both go through it, so they share one approval and one connection; the helper
/// undoes what either has asked for when that connection ends.
@MainActor
final class HelperConnection: ObservableObject {
    enum State: Equatable {
        /// The helper is registered and approved.
        case ready
        /// Registered, waiting for the user to allow it in System Settings → Login Items.
        case needsApproval
        case notInstalled
        /// This copy cannot use a helper, e.g. a development build without a Developer ID.
        case unavailable
    }

    enum Outcome: Equatable {
        case done
        /// The helper is not set up, so nothing was sent.
        case notReady
        case failed(String)
    }

    /// The version for which the user was last asked to set up the helper. The key predates the
    /// helper doing more than fans, and is kept so nobody is asked twice.
    private static let askedVersionKey = "fanHelperAskedVersion"

    /// A request the helper has not answered by then counts as failed.
    private static let replyTimeout: Duration = .seconds(5)

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var setupError: String?
    /// The helper is registered but did not answer; registering it again usually clears it.
    @Published private(set) var isUnresponsive = false

    /// Fires when the connection ends: the helper has then handed everything back to macOS.
    let connectionEnded = PassthroughSubject<Void, Never>()

    private let service = SMAppService.daemon(plistName: FanControlLimits.helperPlist)
    private let team = FanControlLimits.signingTeam()
    private var connection: NSXPCConnection?

    init() {
        refreshState()
    }

    /// Whether anything this Mac can do needs the helper.
    var isNeeded: Bool { FanController.macHasFans || KeepAwakeController.isAvailable }

    func refreshState() {
        guard team != nil else {
            state = .unavailable
            return
        }
        state = switch service.status {
        case .enabled: .ready
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .notInstalled
        }
    }

    /// Registers the helper; macOS then asks for approval in System Settings, which is opened.
    func install() {
        setupError = nil
        do {
            try service.register()
        } catch {
            setupError = L("Could not set up the helper: %@", error.localizedDescription)
        }
        refreshState()
        if state == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Asks once per version, on a Mac that has a use for the helper, when it is not set up or macOS
    /// wants it approved again (as can happen after an update). "Not now" is remembered until the
    /// next version.
    func askForApprovalIfNeeded(defaults: UserDefaults = .standard) {
        refreshState()
        let version = AppIdentity.versionText
        guard
            isNeeded, state == .notInstalled || state == .needsApproval,
            defaults.string(forKey: Self.askedVersionKey) != version
        else { return }
        defaults.set(version, forKey: Self.askedVersionKey)

        let alert = NSAlert()
        alert.messageText = L("Set up Sysbar's helper?")
        alert.informativeText = state == .needsApproval
            ? L("macOS needs you to allow Sysbar's helper again in System Settings → General → Login Items.")
            : L("Sysbar can run the fans faster or slower, and keep your Mac awake with the lid closed, when you choose to. This needs a small helper that macOS asks you to approve once. You can also do this later in Settings.")
        alert.addButton(withTitle: state == .needsApproval ? L("Open System Settings") : L("Set up…"))
        alert.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if state == .needsApproval { openApprovalSettings() } else { install() }
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

    /// Ending the connection makes the helper hand back the fans and the Mac's sleep.
    func uninstall() async {
        connection?.invalidate()
        connection = nil
        do {
            try await service.unregister()
        } catch {
            setupError = L("Could not remove the helper: %@", error.localizedDescription)
        }
        refreshState()
    }

    /// Whether a connection is open, i.e. whether the helper may be holding something for Sysbar.
    var isConnected: Bool { connection != nil }

    /// Runs one request on the helper.
    func perform(_ request: @escaping (FanControlProtocol, @escaping (String?) -> Void) -> Void) async -> Outcome {
        refreshState()
        guard state == .ready, let connection = openConnection() else { return .notReady }
        let timeout = L("The helper did not answer.")
        let failure: String? = await withCheckedContinuation { continuation in
            let once = ReplyOnce(continuation)
            Task {
                try? await Task.sleep(for: Self.replyTimeout)
                once.resume(timeout)
            }
            let remote = connection.remoteObjectProxyWithErrorHandler { error in once.resume(error.localizedDescription) }
            guard let helper = remote as? FanControlProtocol else {
                once.resume(timeout)
                return
            }
            request(helper) { once.resume($0) }
        }
        isUnresponsive = failure == timeout
        return failure.map(Outcome.failed) ?? .done
    }

    private func openConnection() -> NSXPCConnection? {
        if let connection { return connection }
        guard let team else { return nil }
        let connection = NSXPCConnection(machServiceName: FanControlLimits.helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanControlProtocol.self)
        connection.setCodeSigningRequirement(
            FanControlLimits.requirement(identifier: FanControlLimits.helperLabel, team: team)
        )
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor in
                guard let self else { return }
                // A late callback from a connection that has been replaced must not end the new one.
                if self.connection != nil, self.connection !== connection { return }
                self.connection = nil
                self.connectionEnded.send()
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
