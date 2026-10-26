import CoreGraphics
import Testing

@testable import SysbarCore

/// A random source that repeats for the same seed, so a route can be checked exactly.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Mouse wander timing")
struct MouseWanderTimingTests {
    @Test("moves only after a full minute without input")
    func dueAfterAMinute() {
        #expect(MouseWander.isDue(idleSeconds: 59.9) == false)
        #expect(MouseWander.isDue(idleSeconds: 60) == true)
        #expect(MouseWander.isDue(idleSeconds: 600) == true)
    }

    @Test("a fresh input is never due")
    func notDueRightAfterInput() {
        #expect(MouseWander.isDue(idleSeconds: 0) == false)
    }
}

@Suite("Mouse wander routes")
struct MouseWanderRouteTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let origin = CGPoint(x: 700, y: 400)

    private func route(seed: UInt64, from start: CGPoint? = nil) -> MouseRoute {
        var generator = SeededGenerator(seed: seed)
        return MouseWander.route(from: start ?? origin, within: screen, using: &generator)
    }

    @Test("starts and ends exactly where the cursor rested")
    func returnsToOrigin() {
        for seed in 1...50 as ClosedRange<UInt64> {
            let route = route(seed: seed)
            let start = route.position(at: 0)
            let end = route.position(at: route.totalSeconds)
            #expect(start == origin)
            #expect(end == origin)
        }
    }

    @Test("goes to the middle of the screen, and stops there for a moment")
    func reachesTheCenter() {
        let center = CGPoint(x: screen.midX, y: screen.midY)
        for seed in 1...50 as ClosedRange<UInt64> {
            let route = route(seed: seed, from: CGPoint(x: 200, y: 150))
            let far = route.position(at: route.outSeconds + route.dwellSeconds / 2)
            #expect(far == center)
            let before = route.position(at: route.outSeconds)
            let after = route.position(at: route.outSeconds + route.dwellSeconds)
            #expect(before == after)
        }
    }

    @Test("a cursor already near the middle goes to the lower right instead, clear of the corner")
    func goesToTheLowerRightFromTheMiddle() {
        let lowerRight = CGPoint(x: screen.maxX - screen.width * MouseWander.cornerInset, y: screen.maxY - screen.height * MouseWander.cornerInset)
        for start in [CGPoint(x: screen.midX, y: screen.midY), CGPoint(x: screen.midX + 150, y: screen.midY - 100)] {
            let target = MouseWander.target(from: start, within: screen)
            #expect(target == lowerRight)
            #expect(target.x < screen.maxX - 100)
            #expect(target.y < screen.maxY - 100)
        }
    }

    @Test("a cursor away from the middle goes to the middle")
    func goesToTheMiddleFromElsewhere() {
        let center = CGPoint(x: screen.midX, y: screen.midY)
        for start in [CGPoint(x: 10, y: 10), CGPoint(x: screen.maxX - 5, y: screen.maxY - 5), CGPoint(x: screen.midX + 300, y: screen.midY)] {
            #expect(MouseWander.target(from: start, within: screen) == center)
        }
    }

    @Test("never leaves the screen, even from its corner")
    func staysOnScreen() {
        let corner = CGPoint(x: 2, y: 2)
        for seed in 1...50 as ClosedRange<UInt64> {
            let route = route(seed: seed, from: corner)
            for step in 0...200 {
                let point = route.position(at: route.totalSeconds * Double(step) / 200)
                #expect(screen.contains(point))
            }
        }
    }

    @Test("takes a human length of time, longer for a longer way")
    func durations() {
        for seed in 1...50 as ClosedRange<UInt64> {
            let route = route(seed: seed, from: CGPoint(x: 5, y: 5))
            #expect(route.outSeconds > MouseWander.outDurations.lowerBound)
            #expect(route.backSeconds > MouseWander.backDurations.lowerBound)
            #expect(MouseWander.dwellDurations.contains(route.dwellSeconds))
            #expect(route.totalSeconds < 3.5)
        }
    }

    @Test("the same seed gives the same route and different seeds differ")
    func variesBetweenRoutes() {
        #expect(route(seed: 7) == route(seed: 7))
        #expect(route(seed: 7) != route(seed: 8))
    }

    @Test("the way out and the way back are not the same path")
    func backIsNotARewind() {
        var differing = 0
        for seed in 1...50 as ClosedRange<UInt64> {
            let route = route(seed: seed)
            let out = route.position(at: route.outSeconds * 0.5)
            let back = route.position(at: route.outSeconds + route.dwellSeconds + route.backSeconds * 0.5)
            // The mid-point of the way back lies off the mid-point of the way out.
            if abs(out.x - back.x) > 0.5 || abs(out.y - back.y) > 0.5 { differing += 1 }
        }
        #expect(differing > 40)
    }
}
