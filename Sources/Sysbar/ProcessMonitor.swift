import Foundation
import SysbarCore

/// Samples per-app usage on a low-priority timer. It only runs while the popover is open, so the
/// process scan costs nothing the rest of the time.
final class ProcessMonitor {
    private let queue = DispatchQueue(label: "sysbar.processes", qos: .utility)
    private let onUpdate: ([AppUsage]) -> Void
    private var timer: DispatchSourceTimer?

    init(onUpdate: @escaping ([AppUsage]) -> Void) {
        self.onUpdate = onUpdate
    }

    deinit {
        stop()
    }

    func start(interval: TimeInterval, readsNetwork: Bool) {
        guard timer == nil else { return }
        let sampler = ProcessSampler(readsNetwork: readsNetwork)
        queue.async { sampler.prime() }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: interval, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            let usage = sampler.sample()
            DispatchQueue.main.async { self?.onUpdate(usage) }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
