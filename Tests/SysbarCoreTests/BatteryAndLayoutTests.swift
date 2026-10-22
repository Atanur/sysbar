import Foundation
import Testing
@testable import SysbarCore

/// The registry reports current as an unsigned 64-bit number, so a discharge shows up wrapped.
private func amperage(_ milliamps: Int64) -> NSNumber {
    NSNumber(value: UInt64(bitPattern: milliamps))
}

private let dischargingProperties: [String: Any] = [
    "BatteryInstalled": true, "CurrentCapacity": 67, "MaxCapacity": 100,
    "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
    "TimeRemaining": 267, "AvgTimeToEmpty": 267, "AvgTimeToFull": 65_535,
    "CycleCount": 770, "Voltage": 11_652, "Amperage": amperage(-638),
    "BatteryData": ["NominalChargeCapacity": 5_082, "DesignCapacity": 6_075],
    "AdapterDetails": ["FamilyCode": 0],
]

private let chargingProperties: [String: Any] = [
    "BatteryInstalled": true, "CurrentCapacity": 78, "MaxCapacity": 100,
    "ExternalConnected": true, "IsCharging": true, "FullyCharged": false,
    "TimeRemaining": 65_535, "AvgTimeToEmpty": 65_535, "AvgTimeToFull": 45,
    "CycleCount": 770, "Voltage": 12_000, "Amperage": amperage(1_500),
    "BatteryData": ["NominalChargeCapacity": 5_082, "DesignCapacity": 6_075],
    "AdapterDetails": ["Watts": 96],
]

@Suite struct BatteryParsingTests {
    @Test func readsADischargingBattery() throws {
        let battery = try #require(BatteryProbe.parse(dischargingProperties))

        #expect(battery.fraction == 0.67)
        #expect(!battery.isPluggedIn)
        #expect(!battery.isCharging)
        #expect(!battery.isFull)
        #expect(battery.minutesRemaining == 267)
        #expect(battery.cycleCount == 770)
        #expect(abs(try #require(battery.health) - 5_082.0 / 6_075.0) < 1e-9)
        #expect(abs(try #require(battery.batteryWatts) - (-0.638 * 11.652)) < 1e-9)
        #expect(battery.adapterWatts == nil)
    }

    @Test func readsAChargingBatteryOnAnAdapter() throws {
        let battery = try #require(BatteryProbe.parse(chargingProperties))

        #expect(battery.isPluggedIn)
        #expect(battery.isCharging)
        #expect(battery.minutesRemaining == 45, "while charging the estimate is the time to full")
        #expect(battery.adapterWatts == 96)
        #expect(abs(try #require(battery.batteryWatts) - 18.0) < 1e-9)
    }

    @Test func aFullBatteryHasNoEstimate() throws {
        var properties = chargingProperties
        properties["IsCharging"] = false
        properties["FullyCharged"] = true
        properties["AvgTimeToFull"] = 65_535

        let battery = try #require(BatteryProbe.parse(properties))

        #expect(battery.isFull)
        #expect(battery.minutesRemaining == nil)
    }

    @Test func machinesWithoutABatteryReturnNil() {
        #expect(BatteryProbe.parse([:]) == nil)
        #expect(BatteryProbe.parse(["BatteryInstalled": false, "CurrentCapacity": 0, "MaxCapacity": 0]) == nil)
    }
}

@Suite struct PowerSummaryTests {
    private func battery(
        fraction: Double = 0.67, plugged: Bool = false, charging: Bool = false, full: Bool = false,
        minutes: Int? = nil, cycles: Int? = nil, health: Double? = nil, adapter: Int? = nil, watts: Double? = nil
    ) -> BatteryInfo {
        BatteryInfo(
            fraction: fraction, isPluggedIn: plugged, isCharging: charging, isFull: full,
            minutesRemaining: minutes, cycleCount: cycles, health: health, adapterWatts: adapter, batteryWatts: watts
        )
    }

    @Test func headlineShowsChargeAndTimeLeftOnBattery() {
        #expect(PowerSummary.headline(battery: battery(minutes: 267)) == "67% · 4h 27m")
        #expect(PowerSummary.headline(battery: battery()) == "67%")
    }

    @Test func headlineSaysWhetherThePluggedInBatteryIsChargingOrFull() {
        #expect(PowerSummary.headline(battery: battery(fraction: 0.78, plugged: true, charging: true)) == "78% · charging")
        #expect(PowerSummary.headline(battery: battery(fraction: 1, plugged: true, full: true)) == "100% · on power")
    }

    @Test func headlineIsNilWithoutABattery() {
        #expect(PowerSummary.headline(battery: nil) == nil)
    }

    @Test func detailOnBatteryShowsDrainCyclesAndHealth() {
        let detail = PowerSummary.detail(
            battery: battery(cycles: 770, health: 0.8365, watts: -7.43), systemPower: 7.5
        )

        #expect(detail == "Battery draw 7.4 W · 770 cycles · health 84%")
    }

    @Test func detailOnAnAdapterShowsWhatIsDrawnFromTheWall() {
        let detail = PowerSummary.detail(
            battery: battery(plugged: true, charging: true, minutes: 45, adapter: 96, watts: 12.4), systemPower: 12.3
        )

        // wall draw = system power + the power going into the battery
        #expect(detail == "Adapter 96 W · ~25 W from the wall · charging +12 W · full in 45m")
    }

    @Test func detailWhenFullOmitsTheChargeRate() {
        let detail = PowerSummary.detail(
            battery: battery(fraction: 1, plugged: true, full: true, adapter: 96, watts: 0), systemPower: 8.4
        )

        #expect(detail == "Adapter 96 W · ~8 W from the wall")
    }

    @Test func detailIsNilWhenThereIsNothingToSay() {
        #expect(PowerSummary.detail(battery: nil, systemPower: 5) == nil)
        #expect(PowerSummary.detail(battery: battery(), systemPower: nil) == nil)
    }
}

@Suite struct DurationAndLayoutTests {
    @Test func compactDurationUsesHoursAndMinutes() {
        #expect(Format.compactDuration(minutes: 267) == "4h 27m")
        #expect(Format.compactDuration(minutes: 45) == "45m")
        #expect(Format.compactDuration(minutes: 60) == "1h")
        #expect(Format.compactDuration(minutes: 61) == "1h 1m")
    }

    @Test func automaticLayoutUsesTwoColumnsOnlyForAnEvenCount() {
        #expect([0, 1, 3, 5, 7].map { CardLayout.columns(forCount: $0) } == [1, 1, 1, 1, 1])
        #expect([2, 4, 6].map { CardLayout.columns(forCount: $0) } == [2, 2, 2])
    }

    @Test func chosenLayoutsOverrideTheCount() {
        #expect([1, 2, 5].map { CardLayout.columns(forCount: $0, mode: .oneColumn) } == [1, 1, 1])
        #expect([1, 2, 5].map { CardLayout.columns(forCount: $0, mode: .twoColumns) } == [1, 2, 2])
    }
}
