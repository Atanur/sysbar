import AppKit
import SysbarCore

/// What the menu bar item shows while Sysbar starts and has no reading yet: the app's logo, its
/// three level bars rising and falling in a wave. It ends with the first reading, but not before it
/// has played for a moment, so it is not a flash. With reduced motion the logo stands still.
@MainActor
final class LaunchAnimation {
    private static let framesPerSecond = 24.0
    private static let waveSeconds = 0.9
    private static let minimumSeconds = 1.2
    private static let barCount = 3
    /// How far each bar lags the one before it, in turns of the wave.
    private static let barLag = 0.14
    /// The lowest a bar falls to, as a share of its height.
    private static let lowestLevel = 0.15

    private(set) var isPlaying = false
    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var startedAt = Date()
    private var onFinished: (() -> Void)?

    func start(on button: NSStatusBarButton) {
        button.imagePosition = .imageOnly
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            button.image = MenuBarLogo.image()
            return
        }
        self.button = button
        startedAt = Date()
        isPlaying = true
        draw()
        let timer = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Keeps running while a menu or the popover is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ends the animation once it has played for its minimum time, then calls `done`. Asked again
    /// before then, it only replaces `done`.
    func finish(then done: @escaping () -> Void) {
        onFinished = done
        if elapsed >= Self.minimumSeconds { end() }
    }

    private var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    private func tick() {
        if onFinished != nil, elapsed >= Self.minimumSeconds {
            end()
        } else {
            draw()
        }
    }

    private func end() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        let done = onFinished
        onFinished = nil
        done?()
    }

    private func draw() {
        button?.image = Self.image(at: elapsed)
    }

    private static func image(at time: TimeInterval) -> NSImage {
        let levels = (0..<barCount).map { index -> Double in
            let turn = time / waveSeconds - Double(index) * barLag
            return lowestLevel + (1 - lowestLevel) * (0.5 + 0.5 * sin(2 * .pi * turn))
        }
        return MenuBarLogo.image(levels: levels)
    }
}
