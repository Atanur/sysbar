import AppKit
import ApplicationServices
import OSLog
import SysbarCore

/// Moves the mouse cursor a little, about once a minute, while nobody has touched the Mac, so chat
/// apps that read the system's idle clock do not show "away". It runs only while keep awake is on.
///
/// Posting input events needs the Accessibility permission; without it nothing happens.
@MainActor
final class MouseMover {
    private static let log = Logger(subsystem: "com.atanur.sysbar", category: "mouse")
    /// The pause between two positions along a route; shorter than a display's refresh, so each
    /// frame has a fresh position and the cursor does not stutter.
    private static let frameMilliseconds = 8
    /// `kCGAnyInputEventType`: not `.null`, which means "the last null event" and never happens.
    private static let anyInputEvent = CGEventType(rawValue: 0xFFFF_FFFF)!

    private var task: Task<Void, Never>?

    static var hasAccess: Bool { AXIsProcessTrusted() }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MouseWander.pollSeconds))
                guard !Task.isCancelled else { return }
                await self?.moveIfIdle()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func moveIfIdle() async {
        guard Self.hasAccess, Self.isLeftAlone else { return }
        guard let origin = CGEvent(source: nil)?.location else { return }
        var generator = SystemRandomNumberGenerator()
        let route = MouseWander.route(from: origin, within: Self.displayBounds(containing: origin), using: &generator)
        Self.log.info("Moving the mouse after \(Int(Self.idleSeconds), privacy: .public) s of no input")
        await follow(route)
    }

    /// Nobody has used the Mac for a minute, the screen is on and unlocked, and no button is held.
    private static var isLeftAlone: Bool {
        guard MouseWander.isDue(idleSeconds: idleSeconds), NSEvent.pressedMouseButtons == 0 else { return false }
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return false }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool != true
    }

    private static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
    }

    /// Plays the route in step with the clock: each position is due at a fixed time from the start,
    /// not a pause after the last one, so small delays do not add up into stutter. If it is cut short,
    /// the cursor goes back to where it was.
    private func follow(_ route: MouseRoute) async {
        let clock = ContinuousClock()
        let start = clock.now
        let frames = max(1, Int(route.totalSeconds * 1000) / Self.frameMilliseconds)
        for frame in 0...frames {
            guard !Task.isCancelled else { break }
            let elapsed = route.totalSeconds * Double(frame) / Double(frames)
            Self.post(at: route.position(at: elapsed))
            guard frame < frames else { return }
            try? await clock.sleep(until: start.advanced(by: .seconds(route.totalSeconds * Double(frame + 1) / Double(frames))))
        }
        Self.post(at: route.position(at: 0))
    }

    private static func post(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// The screen the cursor is on, or the main one.
    private static func displayBounds(containing point: CGPoint) -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let bounds = displays.map { CGDisplayBounds($0) }.first { $0.contains(point) }
        return bounds ?? CGDisplayBounds(CGMainDisplayID())
    }
}
