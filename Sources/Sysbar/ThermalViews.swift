import SysbarCore
import SwiftUI

/// The top bar's temperature and fan button: just a fan, since the panel it opens has the
/// numbers. It takes the accent colour while the fans are under manual control, and the warning
/// colour when the heat needs attention.
struct ThermalButton: View {
    let assessment: ThermalAssessment?
    let unit: TemperatureUnit
    let isManual: Bool
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "fan")
                .font(.body)
                .foregroundStyle(style)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(isOpen ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(assessment.map { "\($0.cause.title) · \($0.source.title) \(unit.format(celsius: $0.celsius))" } ?? L("Temperature and fans"))
        .accessibilityLabel(L("Temperature and fans"))
        .accessibilityValue(assessment.map { "\($0.cause.title), \($0.source.title) \(unit.format(celsius: $0.celsius))" } ?? "")
    }

    private var style: AnyShapeStyle {
        if isManual { return AnyShapeStyle(.tint) }
        if let assessment, assessment.needsAttention { return AnyShapeStyle(assessment.level.color) }
        return AnyShapeStyle(.secondary)
    }
}

/// Opens under the top bar: what is warming the Mac and why, each part's temperature, and the
/// fans with their automatic or manual control.
struct ThermalPanel: View {
    let assessment: ThermalAssessment?
    let reading: ThermalReading?
    let unit: TemperatureUnit
    @ObservedObject var fans: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let assessment {
                summary(assessment)
            } else {
                Text(L("This Mac's temperature sensors cannot be read.")).font(.caption).foregroundStyle(.secondary)
            }
            if let reading, !reading.temperatures.isEmpty { sources(reading) }
            if let reading, !reading.fans.isEmpty {
                Divider()
                fanControls(reading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// The status dot and title; the longer explanation is the title's tooltip.
    private func summary(_ assessment: ThermalAssessment) -> some View {
        HStack(spacing: 6) {
            Circle().fill(assessment.level.color).frame(width: 7, height: 7)
            Text(assessment.cause.title).font(.callout.weight(.semibold))
            Spacer()
            if let trend = assessment.trendPerMinute, abs(trend) >= 0.5 {
                Text(trendText(trend)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .help(assessment.cause.detail)
        .accessibilityElement(children: .combine)
        .accessibilityHint(assessment.cause.detail)
    }

    private func sources(_ reading: ThermalReading) -> some View {
        HStack(spacing: 6) {
            ForEach(ThermalSource.allCases, id: \.self) { source in
                if let celsius = reading.celsius(source) {
                    let isNamed = source == assessment?.source
                    VStack(spacing: 1) {
                        Text(source.title).font(.caption2).foregroundStyle(.secondary)
                        Text(unit.format(celsius: celsius)).font(.callout.weight(isNamed ? .semibold : .regular)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isNamed ? 0.09 : 0.04))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func fanControls(_ reading: ThermalReading) -> some View {
        HStack {
            Text(L("Fans")).font(.callout.weight(.medium))
            Text(rpmText(reading.fans)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .help(perFanText(reading.fans))
            Spacer()
            ModeSwitch(isManual: modeBinding(reading))
                .disabled(fans.helperState != .ready)
        }
        switch fans.helperState {
        case .ready:
            if case .manual(let fraction) = fans.mode { slider(fraction) }
        case .needsApproval:
            helperNote(L("Allow Sysbar in System Settings → General → Login Items to control the fans.")) {
                Button(L("Open System Settings")) { fans.openApprovalSettings() }
            }
        case .notInstalled:
            helperNote(L("Fan control needs a small helper, set up once with your administrator approval.")) {
                Button(L("Set up…")) { fans.install() }
            }
        case .unavailable:
            helperNote(L("Fan control needs a signed copy of Sysbar.")) { EmptyView() }
        }
        if let error = fans.lastError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(error).font(.caption).foregroundStyle(LoadLevel.high.color)
                Spacer(minLength: 0)
                if fans.isUnresponsive {
                    Button(L("Set up again")) { Task { await fans.reinstall() } }.controlSize(.small)
                }
            }
        }
    }

    private func slider(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(L("Min")).font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(get: { fraction }, set: { fans.setManual($0) }), in: 0...1)
                    .controlSize(.small)
                Text(L("Max")).font(.caption2).foregroundStyle(.secondary)
                Text(Format.percent(fraction)).font(.caption).monospacedDigit().frame(minWidth: 34, alignment: .trailing)
            }
            Text(L("Back to automatic when Sysbar quits or the Mac sleeps."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func helperNote(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action().controlSize(.small)
        }
    }

    /// Switching to manual starts from the fans' current speed, so nothing jumps.
    private func modeBinding(_ reading: ThermalReading) -> Binding<Bool> {
        Binding(
            get: { fans.mode.isManual },
            set: { manual in manual ? fans.setManual(reading.fanFraction ?? 0) : fans.setAutomatic() }
        )
    }

    /// One speed for all fans: their average. Macs with two fans run them separately, so their
    /// speeds differ a little; the tooltip lists each one.
    private func rpmText(_ readings: [FanReading]) -> String {
        let average = readings.map(\.rpm).reduce(0, +) / Double(max(readings.count, 1))
        return L("%@ rpm", "\(Int(average.rounded()))")
    }

    private func perFanText(_ readings: [FanReading]) -> String {
        readings.map { L("Fan %1$@: %2$@ rpm", "\($0.index + 1)", "\(Int($0.rpm.rounded()))") }.joined(separator: "\n")
    }

    private func trendText(_ perMinute: Double) -> String {
        let degrees = unit == .celsius ? perMinute : perMinute * 9 / 5
        let arrow = degrees > 0 ? "↗" : "↘"
        return L("%1$@ %2$@°/min", arrow, Format.decimal(abs(degrees), digits: 1))
    }
}

/// Automatic or Manual, drawn like the popover's tabs. A plain SwiftUI control, so it fades in
/// with the panel without the flashes an AppKit segmented control shows while animating.
private struct ModeSwitch: View {
    @Binding var isManual: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            option(L("Automatic"), selected: !isManual) { isManual = false }
            option(L("Manual"), selected: isManual) { isManual = true }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ThermalSource {
    var title: String {
        switch self {
        case .cpu: L("CPU")
        case .gpu: L("GPU")
        case .memory: L("Memory")
        case .battery: L("Battery")
        }
    }
}

extension ThermalCause {
    var title: String {
        switch self {
        case .throttling: L("Slowing down to cool")
        case .cannotCool: L("Cooling at its limit")
        case .heavyWork: L("Heavy work")
        case .gpuWork: L("Graphics work")
        case .cpuWork: L("Processor work")
        case .coolingDown: L("Cooling down")
        case .warmAtRest: L("Warm at rest")
        case .normal: L("Normal")
        case .cool: L("Cool")
        }
    }

    var detail: String {
        switch self {
        case .throttling: L("macOS is lowering performance to bring the temperature down.")
        case .cannotCool: L("The fans are working hard but the heat is not going away. Check that the vents are free and the Mac is on a hard surface.")
        case .heavyWork: L("The processor and the graphics processor are both busy.")
        case .gpuWork: L("The graphics processor is busy, as when running a language model, rendering or playing a game.")
        case .cpuWork: L("The processor is busy, so its cores are the warmest part.")
        case .coolingDown: L("The load has dropped and the temperature is falling.")
        case .warmAtRest: L("Little is running but the Mac stays warm: heat from earlier work, or warm surroundings.")
        case .normal: L("Temperatures are ordinary for what is running.")
        case .cool: L("Everything is running cool.")
        }
    }
}
