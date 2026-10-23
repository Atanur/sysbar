import AppKit
import Combine
import SysbarCore

/// The app's side of fan control: sends the helper "manual at this speed" or "automatic". Setting
/// the helper up is `HelperConnection`'s job.
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

    /// Only Macs with fans offer fan control. Read once: the SMC key scan is slow.
    static let macHasFans = !ThermalProbe().read().fans.isEmpty

    /// Slider changes are sent once it has rested this long.
    private static let sendDelay: Duration = .milliseconds(250)

    @Published private(set) var mode: Mode = .automatic
    @Published private(set) var lastError: String?

    private let helper: HelperConnection
    private var pendingSend: Task<Void, Never>?
    /// Renews manual mode before the helper's lease runs out.
    private var renewal: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var connectionEnd: AnyCancellable?

    init(helper: HelperConnection) {
        self.helper = helper
        // The helper hands the fans back before sleep; show that after waking.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renewal?.cancel()
                self?.mode = .automatic
            }
        }
        // The helper returns the fans to automatic when the connection ends.
        connectionEnd = helper.connectionEnded.sink { [weak self] in
            MainActor.assumeIsolated {
                // Also ends when the helper is set up again, which is what clears a "did not answer".
                self?.lastError = nil
                self?.renewal?.cancel()
                self?.mode = .automatic
            }
        }
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
        guard helper.isConnected else { return }
        await send { fans, reply in fans.setAutomatic(reply: reply) }
    }

    /// Runs one request on the helper. A failure is shown and the mode falls back to automatic;
    /// the helper itself hands every fan back when a manual request fails part way.
    private func send(_ request: @escaping (FanControlProtocol, @escaping (String?) -> Void) -> Void) async {
        switch await helper.perform(request) {
        case .done:
            lastError = nil
        case .notReady:
            mode = .automatic
        case .failed(let message):
            lastError = message
            renewal?.cancel()
            mode = .automatic
        }
    }
}
