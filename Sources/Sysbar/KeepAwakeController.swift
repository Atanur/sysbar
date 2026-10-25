import AppKit
import Combine
import IOKit.pwr_mgt
import OSLog
import SysbarCore

/// Keeps the Mac awake with its lid closed, through the helper. Lives as long as the app: the
/// popover that shows it is destroyed whenever it closes.
///
/// Like manual fan speed it lasts for this run of Sysbar only: the helper undoes it when Sysbar
/// quits or crashes, or stops renewing it. It also ends on its own when its time is up or the
/// battery runs low. While it is on, the real setting is read back on every renewal, so it
/// follows a change made elsewhere (`pmset disablesleep 0` in Terminal).
///
/// `pmset disablesleep` survives a restart. If the helper dies without undoing it, the next launch
/// finds it still on with `ownedKey` set, and turns it off.
@MainActor
final class KeepAwakeController: ObservableObject {
    /// An app whose being open keeps the Mac awake.
    struct WatchedApp: Hashable {
        let bundleID: String
        let name: String

        /// Whether the app is still open.
        var isRunning: Bool {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
        }
    }

    /// What ends it: a length of time, a time of day, an app being closed or the charger coming out.
    enum Plan: Equatable {
        case duration(KeepAwakeDuration)
        /// Until this moment, worked out from a time of day when it was chosen.
        case until(Date)
        case app(WatchedApp)
        case whileCharging

        var endDate: Date? {
            switch self {
            case .duration(let duration): duration.endDate(from: Date())
            case .until(let date): date
            case .app, .whileCharging: nil
            }
        }
    }

    enum State: Equatable {
        case off
        /// Kept awake by Sysbar; ends at `endsAt`, if it has an end.
        case on(Plan, endsAt: Date?)
        /// On, but set by someone else (e.g. in Terminal). Sysbar shows it and can turn it off.
        case outside
    }

    /// Only laptops have a lid. A Mac without one is kept from sleeping by an assertion held by this
    /// app instead of through the helper. Read once; `--no-lid` makes a laptop act like a desktop, to try it.
    static let hasLid = BatteryProbe.read() != nil && !CommandLine.arguments.contains("--no-lid")

    /// What the feature is called: it is about the lid only where there is one.
    static var title: String { hasLid ? L("Keep awake with the lid closed") : L("Keep awake") }

    /// Set while Sysbar has the setting on, so a later launch knows the setting is Sysbar's to undo.
    private static let ownedKey = "keepAwakeSetBySysbar"

    /// Why it ended by itself, for anyone finding out afterwards (Console, subsystem com.atanur.sysbar).
    private static let log = Logger(subsystem: "com.atanur.sysbar", category: "keep-awake")
    /// Tries per renewal, and the pause between them; the helper's lease is 15 s, a renewal comes every 5 s.
    private static let renewAttempts = 3
    private static let retryDelaySeconds = 1.5

    @Published private(set) var state: State = .off {
        didSet { updateActivity() }
    }
    @Published private(set) var lastError: String?
    /// Why it last ended by itself, until the user starts it again.
    @Published private(set) var stopReason: KeepAwakeStop?

    private let helper: HelperConnection
    private let defaults: UserDefaults
    /// The request in flight, then the renewal loop.
    private var task: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var quitObserver: NSObjectProtocol?
    private var connectionEnd: AnyCancellable?
    /// Whether the app it is kept awake for is still open; ends only after it stayed closed a while.
    private var appPresence = AppPresence()
    /// Held while it is on, so App Nap (this app has no windows, and the lid is closed) cannot
    /// delay the renewals past the helper's lease.
    private var activity: NSObjectProtocol?
    /// Held while it is on, on a Mac without a lid: macOS then does not sleep when idle.
    private var sleepAssertion: IOPMAssertionID?

    init(helper: HelperConnection, defaults: UserDefaults = .standard) {
        self.helper = helper
        self.defaults = defaults
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFromSystem() }
        }
        // The app it is kept awake for may be closed; the samples would notice only later.
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate(battery: nil) }
        }
        // The helper undoes it when the connection ends.
        connectionEnd = helper.connectionEnded.sink { [weak self] in
            MainActor.assumeIsolated { self?.connectionDidEnd() }
        }
    }

    /// On a normal quit the helper undoes the setting as the connection closes, so the next launch
    /// has nothing of ours to find; only a crash leaves the key for it.
    func appWillTerminate() {
        defaults.removeObject(forKey: Self.ownedKey)
    }

    /// On, whether Sysbar or someone else turned it on.
    var isActive: Bool { state != .off }

    func start(_ plan: Plan) {
        task?.cancel()
        lastError = nil
        stopReason = nil
        appPresence = AppPresence()
        state = .on(plan, endsAt: plan.endDate)
        defaults.set(true, forKey: Self.ownedKey)
        task = Task { [weak self] in
            guard let self else { return }
            guard await self.send(enabled: true) else {
                // Not when it was stopped or started again meanwhile: that is the newer request's state.
                if !Task.isCancelled {
                    self.state = .off
                    if !self.helper.isConnected { self.defaults.removeObject(forKey: Self.ownedKey) }
                }
                return
            }
            await self.renewUntilEnded()
        }
    }

    func stop(because reason: KeepAwakeStop? = nil) {
        if let reason { Self.log.notice("Keep awake ended: \(String(describing: reason), privacy: .public)") }
        task?.cancel()
        stopReason = reason
        state = .off
        task = Task { [weak self] in
            guard let self else { return }
            if await self.send(enabled: false) {
                // Not when it was started again while this was in flight: that owns the key now.
                if self.state == .off { self.defaults.removeObject(forKey: Self.ownedKey) }
            } else {
                self.refreshFromSystem()
            }
        }
    }

    /// Called with every sample: ends it once its time is up, its app is closed or the battery is low.
    func evaluate(battery: BatteryInfo?, now: Date = Date()) {
        guard case .on(let plan, let endsAt) = state else { return }
        if case .app(let app) = plan, appPresence.isGone(running: app.isRunning, now: now) {
            Self.log.notice("Keep awake ended: \(app.bundleID, privacy: .public) was not running for \(AppPresence.graceSeconds, privacy: .public) s")
            stop(because: .appQuit)
        } else if let reason = KeepAwakePolicy.stopReason(
            now: now, endsAt: endsAt, battery: battery, requiresPower: plan == .whileCharging
        ) {
            stop(because: reason)
        }
    }

    /// The apps open now that could be chosen, by name. Background apps and Sysbar itself are left out.
    static func openApps() -> [WatchedApp] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> WatchedApp? in
            guard
                app.activationPolicy == .regular, !app.isTerminated,
                let id = app.bundleIdentifier, id != own, let name = app.localizedName
            else { return nil }
            return WatchedApp(bundleID: id, name: name)
        }
        return Set(apps).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Brings the shown state in line with the system's: at launch, when the popover opens and
    /// after waking. A setting Sysbar left behind is turned off; one set by someone else is shown.
    func refreshFromSystem() {
        guard Self.hasLid else { return }
        Task { [weak self] in
            guard let actual = await Self.readSetting(), let self else { return }
            switch (self.state, actual) {
            case (.off, true):
                if self.defaults.bool(forKey: Self.ownedKey) {
                    await self.reclaim()
                } else {
                    self.state = .outside
                }
            case (.outside, false):
                self.state = .off
            case (.off, false):
                self.defaults.removeObject(forKey: Self.ownedKey)
            default:
                break
            }
        }
    }

    /// While on: reads the real setting and renews the helper's lease, well inside it.
    private func renewUntilEnded() async {
        // The assertion needs no renewing, and nobody else can undo it.
        while Self.hasLid, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(FanControlLimits.renewSeconds))
            guard !Task.isCancelled, case .on = state else { return }
            let actual = await Self.readSetting()
            guard !Task.isCancelled, case .on = state else { return }
            if actual == false {
                // Turned off elsewhere; drop the helper's claim too.
                Self.log.notice("Keep awake ended: pmset reports the setting is off")
                state = .off
                defaults.removeObject(forKey: Self.ownedKey)
                _ = await send(enabled: false)
                return
            }
            guard await renewLease() else {
                if !Task.isCancelled {
                    Self.log.error("Keep awake ended: the helper did not accept the renewal")
                    state = .off
                }
                return
            }
        }
    }

    /// Renews the helper's lease; a failed request is tried again a couple of times, well inside the
    /// lease, so one dropped message does not end keeping the Mac awake.
    private func renewLease() async -> Bool {
        for attempt in 1...Self.renewAttempts {
            if await send(enabled: true) { return true }
            guard attempt < Self.renewAttempts, !Task.isCancelled else { break }
            try? await Task.sleep(for: .seconds(Self.retryDelaySeconds))
        }
        return false
    }

    /// Turns off a setting an earlier run of Sysbar left behind.
    private func reclaim() async {
        let released = await send(enabled: false)
        // The user may have started it again while this was in flight; that state wins.
        guard state == .off else { return }
        if released {
            defaults.removeObject(forKey: Self.ownedKey)
        } else {
            state = .outside
        }
    }

    private func updateActivity() {
        if case .on = state {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep, reason: "Keeping the Mac awake with its lid closed"
                )
            }
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func connectionDidEnd() {
        // Also ends when the helper is set up again, which is what clears a "did not answer".
        lastError = nil
        if case .on = state {
            Self.log.notice("Keep awake ended: the helper connection closed")
            task?.cancel()
            state = .off
        }
        refreshFromSystem()
    }

    /// Runs one request on the helper; false, with the reason in `lastError`, if it failed.
    private func send(enabled: Bool) async -> Bool {
        guard Self.hasLid else { return setSleepAssertion(held: enabled) }
        let outcome = await helper.perform({ helper, reply in helper.setLidAwake(enabled: enabled, reply: reply) })
        // A request that was replaced meanwhile must not show its outcome.
        let current = !Task.isCancelled
        switch outcome {
        case .done:
            if current { lastError = nil }
            return true
        case .notReady:
            return false
        case .failed(let message):
            if current { lastError = message }
            return false
        }
    }

    /// Takes or drops the assertion that stops the Mac sleeping when idle; false if macOS refused.
    private func setSleepAssertion(held: Bool) -> Bool {
        guard held else {
            if let sleepAssertion { IOPMAssertionRelease(sleepAssertion) }
            sleepAssertion = nil
            return true
        }
        guard sleepAssertion == nil else { return true }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Sysbar is keeping the Mac awake" as CFString, &id
        )
        guard result == kIOReturnSuccess else {
            Self.log.error("Keep awake failed: macOS refused the sleep assertion (\(result, privacy: .public))")
            return false
        }
        sleepAssertion = id
        return true
    }

    private static func readSetting() async -> Bool? {
        await Task.detached { PowerManagementSetting.readSleepDisabled() }.value
    }
}
