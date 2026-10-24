import Foundation
import Testing
@testable import SysbarCore

@Suite struct KeepAwakePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func battery(fraction: Double, plugged: Bool) -> BatteryInfo {
        BatteryInfo(
            fraction: fraction, isPluggedIn: plugged, isCharging: false, isFull: false, minutesRemaining: nil,
            cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
        )
    }

    @Test func timedChoicesEndAfterTheirLengthAndTheOpenOneNever() {
        #expect(KeepAwakeDuration.oneHour.endDate(from: now) == now.addingTimeInterval(3_600))
        #expect(KeepAwakeDuration.fourHours.endDate(from: now) == now.addingTimeInterval(14_400))
        #expect(KeepAwakeDuration.untilOff.endDate(from: now) == nil)
    }

    @Test func itStopsOnceTheTimeIsUp() {
        let end = now.addingTimeInterval(60)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: end, battery: nil) == nil)
        #expect(KeepAwakePolicy.stopReason(now: end, endsAt: end, battery: nil) == .timeUp)
        #expect(KeepAwakePolicy.stopReason(now: end.addingTimeInterval(5), endsAt: end, battery: nil) == .timeUp)
    }

    @Test func withoutAnEndItRunsOn() {
        #expect(KeepAwakePolicy.stopReason(now: now.addingTimeInterval(86_400), endsAt: nil, battery: nil) == nil)
    }

    @Test func itStopsWhenTheBatteryRunsLowOffPower() {
        #expect(KeepAwakePolicy.lowBatteryPercent == 20)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.21, plugged: false)) == nil)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.20, plugged: false)) == .lowBattery)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.05, plugged: false)) == .lowBattery)
    }

    @Test func aLowBatteryOnPowerIsNoReasonToStop() {
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.05, plugged: true)) == nil)
    }

    @Test func timeUpIsReportedBeforeALowBattery() {
        let end = now.addingTimeInterval(-1)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: end, battery: battery(fraction: 0.05, plugged: false)) == .timeUp)
    }
}

@Suite struct KeepAwakeRequiringPowerTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func battery(fraction: Double, plugged: Bool) -> BatteryInfo {
        BatteryInfo(
            fraction: fraction, isPluggedIn: plugged, isCharging: false, isFull: false, minutesRemaining: nil,
            cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
        )
    }

    @Test func itStopsOnceTheChargerIsUnplugged() {
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.9, plugged: true), requiresPower: true) == nil)
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.9, plugged: false), requiresPower: true) == .unplugged)
    }

    @Test func withoutBatteryInformationItKeepsGoing() {
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: nil, requiresPower: true) == nil)
    }

    @Test func unpluggedIsReportedBeforeALowBattery() {
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.05, plugged: false), requiresPower: true) == .unplugged)
    }

    @Test func unpluggingMeansNothingWhenPowerIsNotRequired() {
        #expect(KeepAwakePolicy.stopReason(now: now, endsAt: nil, battery: battery(fraction: 0.9, plugged: false)) == nil)
    }
}

@Suite struct KeepAwakeScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int, day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func aTimeLaterTodayIsToday() {
        let end = KeepAwakeSchedule.nextOccurrence(hour: 18, minute: 30, after: date(9, 0), calendar: calendar)
        #expect(end == date(18, 30))
    }

    @Test func aTimeThatHasPassedIsTomorrow() {
        let end = KeepAwakeSchedule.nextOccurrence(hour: 8, minute: 0, after: date(9, 0), calendar: calendar)
        #expect(end == date(8, 0, day: 16))
    }

    @Test func theTimeItIsRightNowIsTomorrowToo() {
        let end = KeepAwakeSchedule.nextOccurrence(hour: 9, minute: 0, after: date(9, 0), calendar: calendar)
        #expect(end == date(9, 0, day: 16))
    }

    @Test func secondsPastTheMinuteDoNotMoveTheEnd() {
        let now = date(9, 0).addingTimeInterval(40)
        #expect(KeepAwakeSchedule.nextOccurrence(hour: 9, minute: 1, after: now, calendar: calendar) == date(9, 1))
    }
}

@Suite struct AppPresenceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// What each look says, given `(seconds since the start, whether the app was running)`.
    private func looks(_ sequence: [(Double, Bool)]) -> [Bool] {
        var presence = AppPresence()
        return sequence.map { presence.isGone(running: $0.1, now: now.addingTimeInterval($0.0)) }
    }

    @Test func anAppThatIsRunningIsNeverGone() {
        let results = looks(stride(from: 0.0, through: 120, by: 10).map { ($0, true) })
        #expect(!results.contains(true))
    }

    @Test func aSingleMissedLookDoesNotEndIt() {
        let grace = AppPresence.graceSeconds
        // The wait starts over once the app is seen again.
        let results = looks([(0, false), (2, true), (4, false), (4 + grace - 1, false)])
        #expect(results == [false, false, false, false])
    }

    @Test func anAppMissingForTheWholeGracePeriodIsGone() {
        let results = looks([(0, false), (AppPresence.graceSeconds, false)])
        #expect(results == [false, true])
    }
}

@Suite struct PowerManagementSettingTests {
    @Test func readsTheSleepDisabledSettingFromPmsetOutput() {
        let on = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        let off = " SleepDisabled\t\t0\n sleep 1\n"
        #expect(PowerManagementSetting.sleepDisabled(in: on) == true)
        #expect(PowerManagementSetting.sleepDisabled(in: off) == false)
    }

    @Test func aMissingSettingMeansSleepIsAllowed() {
        #expect(PowerManagementSetting.sleepDisabled(in: " sleep 1\n displaysleep 10\n") == false)
        #expect(PowerManagementSetting.sleepDisabled(in: "") == false)
    }

    @Test func otherSettingsThatMentionSleepAreNotMistakenForIt() {
        #expect(PowerManagementSetting.sleepDisabled(in: " DisableSleepOnLid 1\n sleep 1\n") == false)
    }

    @Test func theRealPmsetCanBeReadOnThisMac() throws {
        // The setting's value depends on the machine; that it can be read at all does not.
        #expect(PowerManagementSetting.readSleepDisabled() != nil)
        let output = try #require(PowerManagementSetting.run(["-g"])?.output)
        #expect(output.contains("sleep"))
    }

    @Test func aProcessReturnsItsOutputAndStatus() {
        let echoed = PowerManagementSetting.run(URL(fileURLWithPath: "/bin/echo"), ["hello"], timeout: 5)
        #expect(echoed?.status == 0)
        #expect(echoed?.output == "hello\n")
        #expect(PowerManagementSetting.run(URL(fileURLWithPath: "/usr/bin/false"), [], timeout: 5)?.status == 1)
    }

    @Test func aProcessThatDoesNotFinishInTimeIsKilledAndReportsNothing() {
        let started = Date()
        let result = PowerManagementSetting.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: 0.3)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func aMissingProgramReportsNothing() {
        #expect(PowerManagementSetting.run(URL(fileURLWithPath: "/nonexistent/pmset"), [], timeout: 1) == nil)
    }
}
