import SwiftUI
import SysbarCore

/// One instant of what the power card needs, from this Mac or from a remote one.
struct PowerCardSample {
    /// Best whole-machine figure in watts.
    let headline: Double?
    let battery: BatteryInfo?
    let components: PowerReading?
}

/// Everything the power card shows, built the same way for this Mac and for remote machines: on
/// battery the charge and time left, on an adapter a bolt (green while charging) and what goes into
/// the battery under what the machine uses, and a plain bolt on a Mac without a battery.
struct PowerCardContent {
    let symbol: String
    let value: String
    let note: String
    let noteSymbol: NoteSymbol?
    let help: String
    let series: [Double]
    let secondary: [Double]?
    let readouts: [Readout]
    let load: LoadLevel?
    let tint: Color?

    init(samples: [PowerCardSample]) {
        let latest = samples.last
        let battery = latest?.battery
        series = samples.compactMap(\.headline)

        let note: String
        let noteSymbol: NoteSymbol?
        switch PowerSource(battery: battery) {
        case .battery:
            note = PowerSummary.headline(battery: battery) ?? ""
            noteSymbol = nil
        case .charging:
            note = battery.map { Format.percent($0.fraction) } ?? ""
            noteSymbol = NoteSymbol(systemName: "bolt.fill", color: FlowColors.charge, label: L("charging"))
        case .pluggedIn:
            note = battery.map { Format.percent($0.fraction) } ?? ""
            noteSymbol = NoteSymbol(systemName: "bolt.fill", color: .primary, label: L("on power"))
        case .mains:
            note = ""
            noteSymbol = NoteSymbol(systemName: "bolt.fill", color: .primary, label: L("on power"))
        }
        self.note = note
        self.noteSymbol = noteSymbol

        // With the charger in, what goes into the battery hangs below what the machine itself uses.
        let charge = samples.compactMap { sample in sample.headline.map { _ in Self.chargeWatts(sample.battery) } }
        let showsCharge = charge.contains { $0 > 0 }
        let system = latest?.headline
        let nowCharging = Self.chargeWatts(battery)
        var readouts: [Readout] = []
        if let system, nowCharging > 0 {
            readouts = [
                Readout(text: Format.watts(system), color: FlowColors.draw),
                Readout(text: "+" + Format.watts(nowCharging), color: FlowColors.charge),
            ]
        }
        self.readouts = readouts
        secondary = showsCharge ? charge : nil
        tint = showsCharge ? FlowColors.draw : nil
        load = system.map { LoadLevel(fraction: $0 / MenuBarReadouts.powerFullScaleWatts) }
        symbol = Self.symbol(battery)
        value = system.map(Format.watts) ?? "–"

        // The corner shows the battery state; adapter and wall details are in the tooltip.
        let tooltip = [
            PowerSummary.detail(battery: battery, systemPower: system),
            latest?.components.map(Self.componentText),
            showsCharge ? L("Above the line: what the Mac uses · Below: going into the battery") : nil,
        ].compactMap { $0 }.joined(separator: "\n")
        help = tooltip.isEmpty ? SeriesStats.of(series).map { L("Peak %@", Format.watts($0.max)) } ?? "" : tooltip
    }

    /// Watts going into the battery; zero on battery power or while it is not taking charge.
    private static func chargeWatts(_ battery: BatteryInfo?) -> Double {
        guard let battery, battery.isPluggedIn, let watts = battery.batteryWatts, watts >= 0.5 else { return 0 }
        return watts
    }

    /// The icon follows the situation: a charge level on battery, a plug on an adapter.
    private static func symbol(_ battery: BatteryInfo?) -> String {
        guard let battery else { return "bolt" }
        if battery.isPluggedIn { return battery.isCharging ? "battery.100percent.bolt" : "powerplug" }
        switch battery.fraction {
        case 0.88...: return "battery.100percent"
        case 0.63...: return "battery.75percent"
        case 0.38...: return "battery.50percent"
        case 0.13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Only components with a trustworthy sensor are listed.
    private static func componentText(_ power: PowerReading) -> String {
        [(L("CPU"), power.cpu), (L("GPU"), power.gpu), (L("ANE"), power.ane), (L("RAM"), power.ram)]
            .compactMap { name, watts in watts.map { L("%1$@ %2$@", name, Format.watts($0)) } }
            .joined(separator: " · ")
    }
}
