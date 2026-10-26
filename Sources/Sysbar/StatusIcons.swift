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

/// The fan symbol for each state, drawn still: a dimmed outline when stopped, an outline when
/// automatic, and a filled one in the accent colour when manual. Fans working hard turn the outline
/// amber, orange and red, so how hard they work shows without an animation, which cost more CPU
/// than everything else in the popover while the fans turned.
struct FanIcon: View {
    let state: FanState
    /// How hard the fans work, 0...1.
    let load: Double
    /// The colour of the automatic state, which turns to a warning while the heat needs attention.
    let automaticStyle: AnyShapeStyle
    /// The heat warning wins over the fans' own colour.
    var isHeatWarning = false

    var body: some View {
        Image(systemName: state == .manual ? "fan.fill" : "fan")
            .font(.body)
            .foregroundStyle(style)
            .opacity(state == .stopped ? 0.55 : 1)
            .motion(.easeOut(duration: 0.2), value: state)
    }

    private var style: AnyShapeStyle {
        switch state {
        case .manual: return AnyShapeStyle(.tint)
        case .stopped: return automaticStyle
        case .automatic:
            let level = LoadLevel(fraction: load)
            guard !isHeatWarning, level != .low else { return automaticStyle }
            return AnyShapeStyle(level.cardColor)
        }
    }
}

// MARK: Laptop lid

/// The keep-awake button's symbol: a MacBook while the Mac may sleep, and the same MacBook struck
/// through while it is kept awake with its lid closed. A Mac without a lid has a cup, filled while
/// it is kept awake.
struct KeepAwakeIcon: View {
    /// True while the Mac is kept awake.
    let isKeptAwake: Bool

    var body: some View {
        // Light, so its filled screen and base weigh no more than the fan and the gear beside it.
        Image(systemName: symbol)
            .font(.body.weight(.light))
            .contentTransition(.symbolEffect(.replace))
            .motion(.easeOut(duration: 0.2), value: isKeptAwake)
    }

    private var symbol: String {
        if KeepAwakeController.hasLid { return isKeptAwake ? "macbook.slash" : "macbook" }
        return isKeptAwake ? "cup.and.saucer.fill" : "cup.and.saucer"
    }
}
