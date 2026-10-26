import Foundation
import Testing
@testable import SysbarCore

@Suite struct ThermalAssessmentTests {
    private let fans = [FanReading(index: 0, rpm: 1_200, minimum: 1_200, maximum: 6_000)]

    /// Samples every 5 seconds for `seconds`, oldest first. `celsius` maps the time offset from
    /// the start to each part's temperature.
    private func samples(
        seconds: Double = 150, cpu: Double = 0.1, gpu: Double = 0, fanFraction: Double? = 0,
        pressure: ThermalPressure = .nominal, celsius: (Double) -> [ThermalSource: Double]
    ) -> [Snapshot] {
        stride(from: 0, through: seconds, by: 5).map { offset in
            let fanReadings = fanFraction.map { fraction in
                fans.map { FanReading(index: $0.index, rpm: $0.minimum + ($0.maximum - $0.minimum) * fraction, minimum: $0.minimum, maximum: $0.maximum) }
            } ?? []
            return Snapshot(
                timestamp: Date(timeIntervalSinceReferenceDate: offset), cpuUsage: cpu,
                memory: MemoryReading(usedBytes: 1, totalBytes: 2, pressure: .normal),
                power: nil, systemPower: nil, gpuUsage: gpu,
                thermal: ThermalReading(temperatures: celsius(offset), fans: fanReadings, pressure: pressure)
            )
        }
    }

    @Test func llmWorkIsBlamedOnTheGPU() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.2, gpu: 0.9) { _ in
            [.cpu: 58, .gpu: 78, .memory: 70, .battery: 35]
        }))
        #expect(result.cause == .gpuWork)
        #expect(result.source == .gpu)
        #expect(result.celsius == 78)
        #expect(result.level == .moderate)
    }

    @Test func snapshotExposesBothPartTemperatures() throws {
        let snapshot = try #require(samples(cpu: 0.2, gpu: 0.9) { _ in [.cpu: 58, .gpu: 78] }.first)
        #expect(snapshot.cpuTemperature == 58)
        #expect(snapshot.gpuTemperature == 78)
    }

    @Test func busyProcessorNamesTheCPU() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.8) { _ in [.cpu: 82, .gpu: 50] }))
        #expect(result.cause == .cpuWork)
        #expect(result.source == .cpu)
        #expect(result.level == .high)
    }

    @Test func aBusyGPUNextToAClearlyHotterWorkingCPUIsHeavyWork() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.27, gpu: 0.5) { _ in [.cpu: 74, .gpu: 65] }))
        #expect(result.cause == .heavyWork)
        #expect(result.source == .cpu)
        #expect(result.celsius == 74)
    }

    @Test func bothBusyNamesTheHotterOne() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.7, gpu: 0.7) { _ in [.cpu: 70, .gpu: 76] }))
        #expect(result.cause == .heavyWork)
        #expect(result.source == .gpu)
    }

    @Test func fansFastWhileIdleMeansTheHeatIsNotGoingAway() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.05, fanFraction: 0.9) { _ in [.cpu: 72, .gpu: 66] }))
        #expect(result.cause == .cannotCool)
        #expect(result.level == .high)
    }

    @Test func fansAtTheLimitUnderLoadWhileStillWarming() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.9, fanFraction: 0.95) { offset in
            [.cpu: 84 + offset / 30]
        }))
        #expect(result.cause == .cannotCool)
    }

    @Test func fallingTemperaturesAfterWorkAreCoolingDown() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.05) { offset in [.cpu: 80 - offset / 10] }))
        #expect(result.cause == .coolingDown)
        #expect(try #require(result.trendPerMinute) < -5)
    }

    @Test func warmWithNothingRunningIsWarmAtRest() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.05) { _ in [.cpu: 64, .gpu: 62, .battery: 40] }))
        #expect(result.cause == .warmAtRest)
    }

    @Test func macOSThrottlingComesFirst() throws {
        let result = try #require(ThermalAssessment.assess(samples(cpu: 0.9, pressure: .serious) { _ in [.cpu: 99, .gpu: 70] }))
        #expect(result.cause == .throttling)
        #expect(result.level == .critical)
        #expect(result.source == .cpu)
    }

    @Test func idleAndCoolIsCool() throws {
        let result = try #require(ThermalAssessment.assess(samples(fanFraction: nil) { _ in [.cpu: 40, .gpu: 38, .battery: 30] }))
        #expect(result.cause == .cool)
        #expect(result.fanFraction == nil)
        #expect(result.level == .low)
    }

    @Test func onlyOutOfTheOrdinaryHeatNeedsAttention() throws {
        let busyButOrdinary = try #require(ThermalAssessment.assess(samples(cpu: 0.9) { _ in [.cpu: 88] }))
        #expect(!busyButOrdinary.needsAttention)
        let veryHot = try #require(ThermalAssessment.assess(samples(cpu: 0.9) { _ in [.cpu: 96] }))
        #expect(veryHot.needsAttention)
        let throttling = try #require(ThermalAssessment.assess(samples(pressure: .serious) { _ in [.cpu: 70] }))
        #expect(throttling.needsAttention)
        let blocked = try #require(ThermalAssessment.assess(samples(cpu: 0.05, fanFraction: 0.9) { _ in [.cpu: 72] }))
        #expect(blocked.needsAttention)
        let mildAtRest = try #require(ThermalAssessment.assess(samples(cpu: 0.05) { _ in [.cpu: 64] }))
        #expect(mildAtRest.cause == .warmAtRest)
        #expect(!mildAtRest.needsAttention)
        let hotAtRest = try #require(ThermalAssessment.assess(samples(cpu: 0.05) { _ in [.cpu: 74] }))
        #expect(hotAtRest.needsAttention)
    }

    @Test func batteryIsNamedOnlyWhenItIsTheOnlySensor() {
        let onlyBattery = ThermalReading(temperatures: [.battery: 33], fans: [], pressure: .nominal)
        #expect(ThermalAssessment.hottestSource(onlyBattery)?.source == .battery)
        let both = ThermalReading(temperatures: [.battery: 45, .cpu: 41], fans: [], pressure: .nominal)
        #expect(ThermalAssessment.hottestSource(both)?.source == .cpu)
    }

    @Test func trendNeedsEnoughTimeAndMeasuresDegreesPerMinute() throws {
        let short = samples(seconds: 30) { offset in [.cpu: 50 + offset] }
        let shortLatest = try #require(short.last)
        #expect(ThermalAssessment.trend(short, source: .cpu, latest: shortLatest) == nil)
        let long = samples(seconds: 120) { offset in [.cpu: 50 + offset / 60] }
        let longLatest = try #require(long.last)
        let slope = try #require(ThermalAssessment.trend(long, source: .cpu, latest: longLatest))
        #expect(abs(slope - 1) < 0.001)
    }

    @Test func noTemperaturesMeansNoAssessment() {
        #expect(ThermalAssessment.assess([]) == nil)
        let bare = Snapshot(
            timestamp: .distantPast, cpuUsage: 0, memory: MemoryReading(usedBytes: 1, totalBytes: 2, pressure: .normal),
            power: nil, systemPower: nil
        )
        #expect(ThermalAssessment.assess([bare]) == nil)
    }
}

@Suite struct FanControlTests {
    @Test func targetSpeedStaysInsideTheFansRange() {
        #expect(FanControlLimits.targetRPM(fraction: 0, minimum: 1_200, maximum: 6_000) == 1_200)
        #expect(FanControlLimits.targetRPM(fraction: 0.5, minimum: 1_200, maximum: 6_000) == 3_600)
        #expect(FanControlLimits.targetRPM(fraction: 1, minimum: 1_200, maximum: 6_000) == 6_000)
    }

    @Test func nonsenseRequestsAndRangesAreRefused() {
        #expect(FanControlLimits.targetRPM(fraction: 2, minimum: 1_200, maximum: 6_000) == nil)
        #expect(FanControlLimits.targetRPM(fraction: -1, minimum: 1_200, maximum: 6_000) == nil)
        #expect(FanControlLimits.targetRPM(fraction: .nan, minimum: 1_200, maximum: 6_000) == nil)
        #expect(FanControlLimits.targetRPM(fraction: 0.5, minimum: 6_000, maximum: 1_200) == nil)
        #expect(FanControlLimits.targetRPM(fraction: 0.5, minimum: -5, maximum: 6_000) == nil)
        #expect(FanControlLimits.targetRPM(fraction: 0.5, minimum: 1_200, maximum: 90_000) == nil)
    }

    @Test func fanFractionIsClampedAndAveraged() {
        let fast = FanReading(index: 0, rpm: 7_000, minimum: 1_200, maximum: 6_000)
        let idle = FanReading(index: 1, rpm: 1_000, minimum: 1_200, maximum: 6_000)
        #expect(fast.fraction == 1)
        #expect(idle.fraction == 0)
        #expect(ThermalReading(temperatures: [:], fans: [fast, idle], pressure: .nominal).fanFraction == 0.5)
    }

    @Test func requirementNamesTheIdentifierAndTeam() {
        let rule = FanControlLimits.requirement(identifier: "com.atanur.sysbar", team: "ABCDE12345")
        #expect(rule.contains("identifier \"com.atanur.sysbar\""))
        #expect(rule.contains("subject.OU] = \"ABCDE12345\""))
    }
}
