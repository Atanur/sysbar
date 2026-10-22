import AppKit
import SysbarCore

/// Samples the system on a low-priority timer and delivers snapshots on the main queue.
/// Sampling pauses while the machine or its screens sleep, so it costs nothing then.
final class MonitorService {
    private(set) var interval: TimeInterval

    private let queue = DispatchQueue(label: "sysbar.sampler", qos: .utility)
    private let onSnapshot: (Snapshot) -> Void
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []

    init(interval: TimeInterval, onSnapshot: @escaping (Snapshot) -> Void) {
        self.interval = interval
        self.onSnapshot = onSnapshot
        observePowerEvents()
    }

    deinit {
        stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    func start() {
        guard timer == nil else { return }
        // A fresh sampler per run: the baseline taken before sleep would span the whole sleep.
        let sampler = SystemSampler()
        queue.async { sampler.prime() }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            // A fifth of the interval, at most half a second, so fast sampling stays even and slow sampling saves power.
            leeway: .milliseconds(Int(min(interval * 0.2, 0.5) * 1_000))
        )
        timer.setEventHandler { [weak self] in
            let snapshot = sampler.sample()
            DispatchQueue.main.async { self?.onSnapshot(snapshot) }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Applies a new sampling interval right away.
    func restart(interval newInterval: TimeInterval) {
        stop()
        interval = newInterval
        start()
    }

    private func observePowerEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let pausing: [Notification.Name] = [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]
        let resuming: [Notification.Name] = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]
        observers += pausing.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.stop() }
        }
        observers += resuming.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.start() }
        }
    }
}
