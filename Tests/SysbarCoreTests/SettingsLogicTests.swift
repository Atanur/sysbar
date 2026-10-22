import Foundation
import Testing
@testable import SysbarCore

@Suite struct LoadLevelTests {
    @Test func fractionsMapToLevels() {
        #expect(LoadLevel(fraction: 0.1) == .low)
        #expect(LoadLevel(fraction: 0.5) == .moderate)
        #expect(LoadLevel(fraction: 0.75) == .high)
        #expect(LoadLevel(fraction: 0.9) == .critical)
        #expect(LoadLevel(fraction: 3) == .critical)
    }

    @Test func invalidReadingsDoNotRaiseAnAlarm() {
        #expect(LoadLevel(fraction: .nan) == .low)
        #expect(LoadLevel(fraction: -1) == .low)
    }

    @Test func memoryFollowsPressureBeforeFullness() {
        #expect(LoadLevel.memory(fraction: 0.8, pressure: .normal) == .low)
        #expect(LoadLevel.memory(fraction: 0.95, pressure: .normal) == .moderate)
        #expect(LoadLevel.memory(fraction: 0.2, pressure: .warning) == .high)
        #expect(LoadLevel.memory(fraction: 0.2, pressure: .critical) == .critical)
    }
}

@Suite struct SamplingIntervalTests {
    @Test func graphsKeepTheSameNumberOfPointsSoTheirSpanFollowsTheRate() {
        #expect(SamplingInterval.windowSeconds(for: 0.1) == 15)
        #expect(SamplingInterval.windowSeconds(for: 2) == 300)
        #expect(SamplingInterval.windowSeconds(for: 5) == 750)
    }

    @Test func graphSpanReadsInSecondsBelowTwoMinutesAndMinutesAbove() {
        #expect(SamplingInterval.windowText(for: 0.1) == "15 s")
        #expect(SamplingInterval.windowText(for: 0.6) == "90 s")
        #expect(SamplingInterval.windowText(for: 2) == "5m")
        #expect(SamplingInterval.windowText(for: 5) == "12.5m")
    }

    @Test func localIntervalRunsFromATenthOfASecondToFiveSeconds() {
        #expect(SamplingInterval.localRange == 0.1...5)
        #expect(SamplingInterval.localStep == 0.1)
    }

    @Test func storedLocalValuesAreClampedAndRoundedToTheSliderStep() {
        // A key that was never stored reads back as 0.
        #expect(SamplingInterval.normalized(0) == SamplingInterval.defaultSeconds)
        #expect(SamplingInterval.normalized(-3) == SamplingInterval.defaultSeconds)
        #expect(SamplingInterval.normalized(.nan) == SamplingInterval.defaultSeconds)
        #expect(SamplingInterval.normalized(0.04) == 0.1)
        #expect(SamplingInterval.normalized(7) == 5)
        #expect(SamplingInterval.normalized(2.34) == 2.3)
        #expect(SamplingInterval.normalized(3) == 3)
    }

    @Test func processScanningNeverRunsMoreThanOncePerSecond() {
        #expect(SamplingInterval.processInterval(for: 0.1) == 1)
        #expect(SamplingInterval.processInterval(for: 2) == 2)
    }

    @Test func intervalsFormatWithOneDecimalBelowTenSeconds() {
        #expect(SamplingInterval.text(0.1) == "0.1")
        #expect(SamplingInterval.text(2) == "2.0")
        #expect(SamplingInterval.text(15) == "15")
    }
}

@Suite struct RemoteIntervalTests {
    @Test func remoteMachinesDefaultToFiveSecondsWithinTwoToThirty() {
        #expect(SamplingInterval.remoteDefaultSeconds == 5)
        #expect(SamplingInterval.remoteRange == 2...30)
    }

    @Test func remoteValuesAreClampedToWholeSeconds() {
        #expect(SamplingInterval.normalizedRemote(10) == 10)
        #expect(SamplingInterval.normalizedRemote(0) == SamplingInterval.remoteDefaultSeconds)
        #expect(SamplingInterval.normalizedRemote(0.5) == 2)
        #expect(SamplingInterval.normalizedRemote(7.4) == 7)
        #expect(SamplingInterval.normalizedRemote(90) == 30)
    }
}

@Suite struct SnapshotInterpolationTests {
    private let gib: UInt64 = 1_073_741_824

    private func snapshot(
        cpu: Double, used: UInt64, pressure: MemoryPressure = .normal, systemPower: Double?,
        gpu: Double?, network: IOThroughput?, at seconds: TimeInterval
    ) -> Snapshot {
        Snapshot(
            timestamp: Date(timeIntervalSince1970: seconds), cpuUsage: cpu,
            memory: MemoryReading(usedBytes: used, totalBytes: 16 * gib, pressure: pressure),
            power: PowerReading(cpu: nil, gpu: 1, ane: 0, ram: nil), systemPower: systemPower,
            gpuUsage: gpu, network: network
        )
    }

    @Test func valuesMoveLinearlyBetweenTwoSamples() {
        let from = snapshot(cpu: 0.10, used: 8 * gib, systemPower: 6, gpu: 0.2,
                            network: IOThroughput(inbound: 1_000, outbound: 0), at: 0)
        let to = snapshot(cpu: 0.20, used: 10 * gib, pressure: .warning, systemPower: 10, gpu: 0.4,
                          network: IOThroughput(inbound: 3_000, outbound: 200), at: 2)

        let half = Snapshot.interpolated(from: from, to: to, fraction: 0.5)

        #expect(abs(half.cpuUsage - 0.15) < 1e-12)
        #expect(half.memory.usedBytes == 9 * gib)
        #expect(half.memory.pressure == .warning, "states that are not numbers come from the newer sample")
        #expect(half.systemPower == 8)
        #expect(half.gpuUsage.map { abs($0 - 0.3) < 1e-12 } == true)
        #expect(half.network == IOThroughput(inbound: 2_000, outbound: 100))
        #expect(half.timestamp == Date(timeIntervalSince1970: 1))
    }

    @Test func fractionIsClampedSoTheAnimationNeverOvershoots() {
        let from = snapshot(cpu: 0.1, used: gib, systemPower: 5, gpu: nil, network: nil, at: 0)
        let to = snapshot(cpu: 0.3, used: gib, systemPower: 9, gpu: nil, network: nil, at: 1)

        #expect(Snapshot.interpolated(from: from, to: to, fraction: -1) == Snapshot.interpolated(from: from, to: to, fraction: 0))
        #expect(Snapshot.interpolated(from: from, to: to, fraction: 7) == to)
    }

    @Test func aValueMissingOnEitherSideIsTakenFromTheNewerSample() {
        let from = snapshot(cpu: 0.1, used: gib, systemPower: nil, gpu: 0.5, network: nil, at: 0)
        let to = snapshot(cpu: 0.1, used: gib, systemPower: 7, gpu: nil,
                          network: IOThroughput(inbound: 10, outbound: 10), at: 1)

        let half = Snapshot.interpolated(from: from, to: to, fraction: 0.5)

        #expect(half.systemPower == 7)
        #expect(half.gpuUsage == nil)
        #expect(half.network == IOThroughput(inbound: 10, outbound: 10))
    }

    @Test func memoryShrinkingDoesNotUnderflow() {
        let from = snapshot(cpu: 0, used: 10 * gib, systemPower: nil, gpu: nil, network: nil, at: 0)
        let to = snapshot(cpu: 0, used: 6 * gib, systemPower: nil, gpu: nil, network: nil, at: 1)

        #expect(Snapshot.interpolated(from: from, to: to, fraction: 0.25).memory.usedBytes == 9 * gib)
    }
}

@Suite struct UptimeFormatTests {
    @Test func usesTheTwoLargestUnits() {
        #expect(Format.uptime(59 * 60) == "59m")
        #expect(Format.uptime(3 * 3_600 + 5 * 60) == "3h 5m")
        #expect(Format.uptime(2 * 86_400 + 4 * 3_600) == "2d 4h")
    }
}

@Suite struct SelectionRulesTests {
    @Test func cardsMayBeEmptyButMenuBarMayNot() {
        #expect(MenuBarMetric.toggling(.cpu, in: [.cpu], minimum: 0) == [])
        #expect(MenuBarMetric.toggling(.cpu, in: [.cpu]) == [.cpu])
    }

    @Test func storedSelectionKeepsAnEmptyListAndOrder() {
        #expect(MenuBarMetric.ordered(fromStored: nil) == nil)
        #expect(MenuBarMetric.ordered(fromStored: []) == [])
        #expect(MenuBarMetric.ordered(fromStored: ["power", "cpu", "bogus"]) == [.cpu, .power])
    }

    @Test func widestTextReservesTheSlot() {
        #expect(MenuBarMetric.cpu.widestText == "100%")
        #expect(MenuBarMetric.memory.widestText == "99.9G")
        #expect(MenuBarMetric.allCases.allSatisfy { !$0.widestText.isEmpty })
    }
}

@Suite struct ReadoutLoadTests {
    private let memory = MemoryReading(usedBytes: 8, totalBytes: 10, pressure: .normal)

    @Test func loadLevelsFollowTheMeasuredValues() {
        let busy = Snapshot(
            timestamp: .distantPast, cpuUsage: 0.95, memory: memory, power: nil, systemPower: 6,
            gpuUsage: 0.6, disk: IOThroughput(inbound: 1, outbound: 1)
        )

        let loads = Dictionary(
            uniqueKeysWithValues: MenuBarReadouts.make(from: busy, metrics: MenuBarMetric.allCases).map { ($0.metric, $0.load) }
        )

        #expect(loads[.cpu] == .critical)
        #expect(loads[.gpu] == .moderate)
        #expect(loads[.memory] == .low)
        #expect(loads[.power] == .low)
        #expect(loads[.disk] == .some(nil))
    }
}

@Suite struct SystemInfoTests {
    @Test func probeReportsThisMachine() {
        let info = SystemInfoProbe.read()

        #expect(!info.chip.isEmpty)
        #expect(info.memoryBytes > 0)
        #expect(info.logicalCores > 0)
        #expect(info.uptime > 0)
    }
}

@Suite struct TemperatureTests {
    @Test func formatsWholeDegreesInEitherUnit() {
        #expect(TemperatureUnit.celsius.format(celsius: 63.6) == "64°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: 63.6) == "146°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: 0) == "32°")
    }

    @Test func averageIgnoresSensorsThatAreOffOrNonsense() {
        #expect(CPUTemperatureProbe.average([60, 70, 0, -5, 900, .nan]) == 65)
        #expect(CPUTemperatureProbe.average([]) == nil)
        #expect(CPUTemperatureProbe.average([0, 0]) == nil)
    }

    @Test func thisMacReportsAPlausibleTemperatureWhenItHasSensors() {
        guard let celsius = CPUTemperatureProbe().read() else { return }
        #expect((1.0...130.0).contains(celsius))
    }
}

@Suite struct KeepMonitoringTests {
    @Test func devicesKeepMonitoringFiveMinutesByDefault() {
        let device = RemoteDevice(name: "VPS", host: "vps", user: "", port: nil, identityFile: "")

        #expect(device.keepMonitoring == .minutes(5))
    }

    @Test func choicesSurviveEncodingAndOldDevicesGetTheDefault() throws {
        let device = RemoteDevice(
            name: "VPS", host: "vps", user: "", port: nil, identityFile: "", keepMonitoring: .always
        )
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"VPS","host":"vps","user":"","identityFile":""}"#
        let odd = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"VPS","host":"vps","user":"","identityFile":"","keepMonitoring":"bogus"}"#

        #expect(try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(device)).keepMonitoring == .always)
        #expect(try JSONDecoder().decode(RemoteDevice.self, from: Data(old.utf8)).keepMonitoring == .minutes(5))
        #expect(try JSONDecoder().decode(RemoteDevice.self, from: Data(odd.utf8)).keepMonitoring == .minutes(5))
    }

    @Test func eachChoiceKnowsHowLongItLasts() {
        #expect(KeepMonitoring.off.seconds == 0)
        #expect(KeepMonitoring.minutes(15).seconds == 900)
        #expect(KeepMonitoring.always.seconds == nil)
        #expect(KeepMonitoring.choices.first == .off)
        #expect(KeepMonitoring.choices.last == .always)
    }
}

@Suite struct TotalMemoryFormatTests {
    @Test func wholeSizesDropTheDecimal() {
        #expect(Format.totalMemory(16 * 1_073_741_824) == "16GB")
        #expect(Format.totalMemory(8_000_000 * 1_024) == "7.6GB")
    }
}
