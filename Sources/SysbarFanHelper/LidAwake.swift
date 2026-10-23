import Foundation
import SysbarCore

/// Keeps the Mac awake with its lid closed, by setting `pmset disablesleep`. That setting is
/// system-wide and survives the helper and even a restart, so the helper undoes it itself, but
/// only when it set it: a value the user chose in Terminal is not ours to take back. It has its
/// own lease, separate from the fans', so neither undoes the other. Undone when:
/// - Sysbar stops renewing the request (FanControlLimits.leaseSeconds), e.g. it hangs,
/// - the last client goes away (Sysbar quits or crashes) or the helper is stopped,
/// - Sysbar asks for it to end.
///
/// Every method must run on the fan queue (`FanService.shared.queue`), which serialises it with
/// the fans, the clients and the lease.
final class LidAwakeService: @unchecked Sendable {
    static let shared = LidAwakeService()

    private var lease: DispatchSourceTimer?
    /// True from the moment this process turned the setting on (or took over a setting that was
    /// already on at the user's request) until it has turned it off again.
    private var enabledHere = false

    /// Replies nil on success, or a short reason it failed.
    func set(enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    /// Turns the setting off if this process turned it on, trying twice. Safe to call at any time.
    func restore() {
        lease?.cancel()
        lease = nil
        guard enabledHere else { return }
        if Self.write(false) || Self.write(false) { enabledHere = false }
    }

    private func enable() -> String? {
        if !enabledHere {
            if PowerManagementSetting.readSleepDisabled() != true {
                // Owned from the moment pmset may have changed it, so a failed check is undone too.
                guard Self.run(true) else { return "The Mac could not be kept awake with its lid closed." }
                enabledHere = true
                guard PowerManagementSetting.readSleepDisabled() == true else {
                    restore()
                    return "The Mac could not be kept awake with its lid closed."
                }
            }
            enabledHere = true
        }
        renewLease()
        return nil
    }

    /// Asked for by the user, so it is turned off even if it was on before Sysbar.
    private func disable() -> String? {
        lease?.cancel()
        lease = nil
        guard Self.write(false) else { return "The Mac could not be allowed to sleep again." }
        enabledHere = false
        return nil
    }

    private func renewLease() {
        lease?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: FanService.shared.queue)
        timer.schedule(deadline: .now() + FanControlLimits.leaseSeconds)
        timer.setEventHandler { [weak self] in self?.restore() }
        timer.resume()
        lease = timer
    }

    /// Runs `pmset -a disablesleep`; true if it exited cleanly.
    private static func run(_ on: Bool) -> Bool {
        PowerManagementSetting.run(["-a", "disablesleep", on ? "1" : "0"])?.status == 0
    }

    /// Sets `disablesleep` and reads it back.
    private static func write(_ on: Bool) -> Bool {
        run(on) && PowerManagementSetting.readSleepDisabled() == on
    }
}
