import Foundation
import Testing
@testable import SysbarCore

@Suite struct KeepAwakeOptionsTests {
    @Test func theSwitchUsesTheChosenDurationOrTheLastOne() {
        #expect(KeepAwakeSwitchDefault.untilOff.duration(last: .oneHour) == .untilOff)
        #expect(KeepAwakeSwitchDefault.oneHour.duration(last: .untilOff) == .oneHour)
        #expect(KeepAwakeSwitchDefault.fourHours.duration(last: .untilOff) == .fourHours)
        #expect(KeepAwakeSwitchDefault.lastUsed.duration(last: .fourHours) == .fourHours)
    }

    @Test func storedNamesAreReadBackAndUnknownOnesFallBack() {
        #expect(KeepAwakeSwitchDefault.normalized("oneHour") == .oneHour)
        #expect(KeepAwakeSwitchDefault.normalized(nil) == .untilOff)
        #expect(KeepAwakeSwitchDefault.normalized("soon") == .untilOff)
        #expect(KeepAwakeDuration.normalized("fourHours") == .fourHours)
        #expect(KeepAwakeDuration.normalized("soon") == .untilOff)
    }

    @Test func theLowBatteryLevelIsOneOfTheChoices() {
        #expect(KeepAwakePolicy.lowBatteryChoices == [10, 20, 30])
        #expect(KeepAwakePolicy.normalizedLowBattery(nil) == 20)
        #expect(KeepAwakePolicy.normalizedLowBattery(0) == 20)
        #expect(KeepAwakePolicy.normalizedLowBattery(30) == 30)
    }

    @Test func aHigherLowBatteryLevelEndsItSooner() {
        let battery = BatteryInfo(
            fraction: 0.25, isPluggedIn: false, isCharging: false, isFull: false, minutesRemaining: nil,
            cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
        )
        let now = Date()
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery) == nil)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery, lowBatteryPercent: 30) == .lowBattery)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery, lowBatteryPercent: 10) == nil)
    }

    @Test func theMouseMovesAfterTheChosenIdleTime() {
        #expect(MouseWander.idleChoices == [30, 60, 120, 300])
        #expect(MouseWander.idleChoices.allSatisfy { $0 >= MouseWander.pollSeconds })
        #expect(MouseWander.normalizedIdle(nil) == 60)
        #expect(MouseWander.normalizedIdle(45) == 60)
        #expect(MouseWander.normalizedIdle(120) == 120)
        #expect(MouseWander.isDue(idleSeconds: 59) == false)
        #expect(MouseWander.isDue(idleSeconds: 60))
        #expect(MouseWander.isDue(idleSeconds: 100, after: 120) == false)
        #expect(MouseWander.isDue(idleSeconds: 30, after: 30))
    }
}
