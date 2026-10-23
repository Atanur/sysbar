import AppKit

/// Runs a short animation by calling back with its progress, 0 to 1, at a modest frame rate, then
/// stops. For things drawn by hand, such as the menu bar image. Only one runs at a time: starting
/// another ends the first where it is. Nothing ticks between animations.
@MainActor
final class FrameTimer {
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    func run(duration: TimeInterval, framesPerSecond: Double = 30, onFrame: @escaping (Double) -> Void) {
        cancel()
        let start = Date()
        let timer = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let progress = min(Date().timeIntervalSince(start) / duration, 1)
                onFrame(progress)
                if progress >= 1 {
                    timer.invalidate()
                    if self?.timer === timer { self?.timer = nil }
                }
            }
        }
        // Keeps running while a menu or the popover is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
