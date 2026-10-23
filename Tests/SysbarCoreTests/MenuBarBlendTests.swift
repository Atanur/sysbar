import Testing
@testable import SysbarCore

@Suite struct MenuBarBlendTests {
    private func readout(_ metric: MenuBarMetric, text: String = "10%", level: Double) -> MenuBarReadout {
        MenuBarReadout(
            slot: .metric(metric), label: metric.title, text: text, level: level, load: nil,
            slotCharacters: metric.widestText.count
        )
    }

    @Test func theLevelMovesTheGivenShareOfTheWay() {
        let old = [readout(.cpu, level: 0.2)]
        let new = [readout(.cpu, text: "60%", level: 0.6)]
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 0).first?.level == 0.2)
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 0.5).first?.level == 0.4)
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 1).first?.level == 0.6)
    }

    @Test func theTextIsAlwaysTheNewOne() {
        let old = [readout(.cpu, text: "20%", level: 0.2)]
        let new = [readout(.cpu, text: "60%", level: 0.6)]
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 0.1).first?.text == "60%")
    }

    @Test func aFractionOutsideTheRangeIsClamped() {
        let old = [readout(.cpu, level: 0.2)]
        let new = [readout(.cpu, level: 0.6)]
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 3) == new)
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: -1).first?.level == 0.2)
    }

    @Test func differentSlotsHaveNothingToGlideBetween() {
        let old = [readout(.cpu, level: 0.2)]
        let new = [readout(.cpu, level: 0.6), readout(.memory, level: 0.5)]
        #expect(MenuBarReadouts.blend(from: old, to: new, fraction: 0.5) == new)
        #expect(MenuBarReadouts.blend(from: [], to: new, fraction: 0.5) == new)
    }
}
