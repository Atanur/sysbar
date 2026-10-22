import Foundation
import SysbarCore

/// Polls one remote device. It starts when the device's tab is chosen and keeps going while other
/// tabs are shown; it stops when another remote device is chosen, or once the device's
/// keep-monitoring time after the popover closes runs out (`StatusController` decides when).
///
/// A failed sample ends the session instead of retrying: repeating a rejected login every few
/// seconds is what gets an address banned by tools like fail2ban. The user retries explicitly.
@MainActor
final class RemoteMonitor: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case live
        case failed(String)
    }

    /// The macOS script itself takes over a second, so polling faster than this only queues work.
    static let minimumInterval: TimeInterval = 2

    @Published private(set) var state: State = .idle
    @Published private(set) var history = BoundedHistory<RemoteSnapshot>(capacity: 2)

    private let runner = SSHRunner()
    private var task: Task<Void, Never>?
    /// The device being sampled, or nil when nothing is.
    private(set) var deviceID: UUID?
    /// Devices contacted since launch, so their connections can be closed when the app quits.
    private var contacted: [UUID: RemoteDevice] = [:]

    func start(_ device: RemoteDevice, interval: TimeInterval) {
        stop()
        let interval = max(interval, Self.minimumInterval)
        contacted[device.id] = device
        deviceID = device.id
        state = .connecting
        history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        task = Task { await poll(device, interval: interval) }
    }

    /// Stops sampling. The shared ssh connection is deliberately left open for a short while (see
    /// `SSHCommand.keepAliveSeconds`) rather than closed: opening and closing the popover would
    /// otherwise log in and out of the server every time. It closes itself when the time is up.
    func stop() {
        task?.cancel()
        task = nil
        runner.cancel()
        deviceID = nil
        state = .idle
    }

    /// True while `id` is being sampled without having failed.
    func isMonitoring(_ id: UUID) -> Bool {
        deviceID == id && state != .idle && !isFailed
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Closes every connection this run opened. Called as the app quits, so nothing outlives it.
    func closeConnections() {
        for device in contacted.values { runner.closeConnectionNow(device) }
        contacted = [:]
    }

    private func poll(_ device: RemoteDevice, interval: TimeInterval) async {
        var tracker = RemoteTracker()
        while !Task.isCancelled {
            let result = await runner.run(device)
            if Task.isCancelled { return }

            switch result {
            case .failure(let error):
                state = .failed(error.message)
                return
            case .success(let output):
                guard let raw = RemoteMetricsParser.parse(output) else {
                    state = .failed(L("The server sent an unexpected response."))
                    return
                }
                guard raw.os != .other else {
                    state = .failed(L("This system is not supported. Only Linux and macOS can be monitored."))
                    return
                }
                let snapshot = tracker.ingest(raw, atNanos: clock_gettime_nsec_np(CLOCK_UPTIME_RAW), date: Date())
                history = history.appending(snapshot)
                state = .live
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
