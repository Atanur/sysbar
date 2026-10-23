import SysbarCore
import SwiftUI

// MARK: Fan

/// What the fans are doing, as the top bar's fan button shows it.
enum FanState: Equatable {
    /// Not turning (0 rpm), as on many Macs while they are cool.
    case stopped
    /// Running under macOS's control.
    case automatic
    /// Running at the speed the user set.
    case manual

    /// A reading under this is a fan that is not turning.
    static let stoppedBelowRPM = 1.0

    init(isManual: Bool, rpm: Double?) {
        if isManual {
            self = .manual
        } else if let rpm, rpm < Self.stoppedBelowRPM {
            self = .stopped
        } else {
            self = .automatic
        }
    }

    var accessibilityText: String {
        switch self {
        case .stopped: L("Fans stopped")
        case .automatic: L("Fans automatic")
        case .manual: L("Fans manual")
        }
    }
}

/// The fan symbol for each state: a dimmed, still outline when stopped; an outline that turns when
/// automatic; a filled one in the accent colour that turns when manual. It turns faster the harder
/// the fans work. The angle is worked out from the clock at about 24 frames a second while it
/// turns, in this view only, and not at all while it is still; it exists only while the popover is
/// open. (A repeating SwiftUI animation here once leaked into the whole popover.)
struct FanIcon: View {
    let state: FanState
    /// How hard the fans work, 0...1; sets the turning speed.
    let load: Double
    /// The colour of the automatic state, which turns to a warning while the heat needs attention.
    let automaticStyle: AnyShapeStyle

    /// Where the fan was when it last changed speed, and when: the angle at any moment follows from
    /// these and the clock. It is not an animation, so it cannot bleed into other views' changes.
    private struct Turning {
        var angle = 0.0
        var since = Date()
        var secondsPerTurn = 3.0
        var isSpinning = false

        func angle(at date: Date) -> Double {
            guard isSpinning else { return angle }
            return (angle + date.timeIntervalSince(since) / secondsPerTurn * 360).truncatingRemainder(dividingBy: 360)
        }
    }

    @State private var turning = Turning()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Redrawn about 24 times a second while turning, and not at all while still.
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !turning.isSpinning)) { timeline in
            Image(systemName: state == .manual ? "fan.fill" : "fan")
                .font(.body)
                .foregroundStyle(style)
                .opacity(state == .stopped ? 0.55 : 1)
                .rotationEffect(.degrees(turning.angle(at: timeline.date)))
        }
        .onAppear(perform: retime)
        .onChange(of: spinKey) { retime() }
    }

    private var style: AnyShapeStyle {
        switch state {
        case .stopped, .automatic: automaticStyle
        case .manual: AnyShapeStyle(.tint)
        }
    }

    /// Seconds per turn: slow while idle, quick at full load. Steps, so the animation is not
    /// restarted by every small change of the reading.
    private var secondsPerTurn: Double {
        let step = (min(max(load, 0), 1) * 4).rounded() / 4
        return 3.0 - 2.2 * step
    }

    private var isSpinning: Bool { state != .stopped && !reduceMotion }

    /// Changes when the animation has to start again.
    private var spinKey: String { "\(isSpinning)-\(secondsPerTurn)" }

    /// Carries on from the angle it has now at the new speed, or stops where it is.
    private func retime() {
        let now = Date()
        turning = Turning(
            angle: turning.angle(at: now), since: now, secondsPerTurn: secondsPerTurn, isSpinning: isSpinning
        )
    }
}

// MARK: Laptop lid

/// A laptop's lid seen from the side. `openness` 1 is a lid standing open, 0 one lying shut.
private struct LaptopLid: Shape {
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Drawn on an 18 x 18 grid, scaled to the frame.
        let unit = min(rect.width, rect.height) / 18
        let closedHeight = 2.2, openHeight = 10.0, hinge = 11.8
        let height = closedHeight + (openHeight - closedHeight) * min(max(openness, 0), 1)
        return Path(
            roundedRect: CGRect(
                x: rect.minX + 3.5 * unit, y: rect.minY + (hinge - height) * unit, width: 11 * unit, height: height * unit
            ),
            cornerRadius: 1.2 * unit
        )
    }
}

/// The keyboard half of the laptop.
private struct LaptopBase: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 18
        return Path(
            roundedRect: CGRect(x: rect.minX + 1.5 * unit, y: rect.minY + 12.8 * unit, width: 15 * unit, height: 2.4 * unit),
            cornerRadius: 1.1 * unit
        )
    }
}

/// The keep-awake button's symbol: a laptop with its lid open while the Mac may sleep, and the
/// lid closing over it while it is kept awake.
struct LaptopLidIcon: View {
    /// True while the Mac is kept awake with its lid closed.
    let isKeptAwake: Bool

    var body: some View {
        ZStack {
            LaptopLid(openness: isKeptAwake ? 0 : 1).stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            LaptopLid(openness: isKeptAwake ? 0 : 1).fill().opacity(isKeptAwake ? 1 : 0.12)
            LaptopBase().fill()
        }
        .frame(width: 18, height: 18)
        .motion(.spring(response: 0.4, dampingFraction: 0.72), value: isKeptAwake)
    }
}
