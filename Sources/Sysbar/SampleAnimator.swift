import Foundation
import SysbarCore

/// Moves the popover's reading smoothly from what is on screen to the newest sample, over one
/// sampling interval, so card values count up or down step by step and the graphs' last points
/// glide instead of jumping. The cards therefore trail the newest sample by one interval, and
/// never stall between them. The menu bar is not animated; it is drawn once per sample.
@MainActor
final class SampleAnimator {
    /// Each frame recomputes the cards, so this is kept low; it is still smooth for a graph's end point.
    static let framesPerSecond = 6.0
    /// At or below this interval samples arrive often enough that there is no gap to fill, and
    /// animating would only double the redraws.
    static let minimumAnimatedInterval: TimeInterval = 1

    private let onFrame: (Snapshot) -> Void
    private var from: Snapshot?
    private var to: Snapshot?
    private var startNanos: UInt64 = 0
    private var duration: TimeInterval = 1
    private var timer: DispatchSourceTimer?

    init(onFrame: @escaping (Snapshot) -> Void) {
        self.onFrame = onFrame
    }

    /// The reading on screen right now, or nil before the first sample.
    var current: Snapshot? {
        guard let from, let to else { return to }
        return Snapshot.interpolated(from: from, to: to, fraction: fraction)
    }

    /// Glides from the reading on screen towards `snapshot` when `animated` (the popover is open)
    /// and samples are far enough apart to need it; otherwise takes it over at once.
    func push(_ snapshot: Snapshot, over interval: TimeInterval, animated: Bool) {
        guard let shown = current, animated, interval > Self.minimumAnimatedInterval else {
            stop()
            from = snapshot
            to = snapshot
            onFrame(snapshot)
            return
        }
        from = shown
        to = snapshot
        startNanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        duration = interval
        startTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private var fraction: Double {
        let elapsed = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - startNanos) / 1e9
        return min(elapsed / duration, 1)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let period = 1 / Self.framesPerSecond
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(Int(period * 100)))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard let frame = current else {
            stop()
            return
        }
        onFrame(frame)
        if fraction >= 1 { stop() }
    }
}
