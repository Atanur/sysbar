import Foundation
import Testing
@testable import SysbarCore

@Suite struct HistoryTests {
    @Test func appendingKeepsOnlyNewestItemsWithinCapacity() {
        let history = (1...5).reduce(BoundedHistory<Int>(capacity: 3)) { $0.appending($1) }

        #expect(history.items == [3, 4, 5])
    }

    @Test func appendingDoesNotMutateTheOriginal() {
        let original = BoundedHistory<Int>(capacity: 3).appending(1)

        _ = original.appending(2)

        #expect(original.items == [1])
    }
}

@Suite struct StatsTests {
    @Test func returnsNilForEmptySeries() {
        #expect(SeriesStats.of([]) == nil)
    }

    @Test func computesMinAverageAndMax() {
        let stats = SeriesStats.of([2, 4, 9])

        #expect(stats == SeriesStats(min: 2, average: 5, max: 9))
    }
}

@Suite struct CPUUsageTests {
    @Test func fractionIsBusyTicksOverTotalTicks() {
        let previous = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let current = CPUTicks(user: 130, system: 70, idle: 850, nice: 0)

        // busy = 30 + 20 = 50, total = 100
        #expect(CPUUsage.fraction(from: previous, to: current) == 0.5)
    }

    @Test func fractionIsZeroWhenNoTicksElapsed() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)

        #expect(CPUUsage.fraction(from: ticks, to: ticks) == 0)
    }

    @Test func fractionSurvivesCounterWraparound() {
        let previous = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)

        // user advanced by 20 (wrapped), idle by 20
        #expect(CPUUsage.fraction(from: previous, to: current) == 0.5)
    }
}

@Suite struct MemoryTests {
    @Test func usedBytesMatchesActivityMonitorFormula() {
        let pages = VMPages(internal: 1000, purgeable: 200, wired: 300, compressed: 100)

        // (1000 - 200 + 300 + 100) * 16 KiB
        #expect(MemoryProbe.usedBytes(pages: pages, pageSize: 16_384) == 1_200 * 16_384)
    }

    @Test func purgeableLargerThanInternalDoesNotUnderflow() {
        let pages = VMPages(internal: 10, purgeable: 50, wired: 5, compressed: 5)

        #expect(MemoryProbe.usedBytes(pages: pages, pageSize: 4_096) == 10 * 4_096)
    }

    @Test func pressureLevelsMapFromKernelValues() {
        #expect(MemoryPressure(kernelLevel: 1) == .normal)
        #expect(MemoryPressure(kernelLevel: 2) == .warning)
        #expect(MemoryPressure(kernelLevel: 4) == .critical)
        #expect(MemoryPressure(kernelLevel: 99) == .normal)
    }
}

@Suite struct EnergyChannelTests {
    @Test func classifiesKnownChannels() {
        #expect(EnergyChannel.component(forChannel: "GPU Energy") == .gpu)
        #expect(EnergyChannel.component(forChannel: "PACC0_CPU Energy") == .cpu)
        #expect(EnergyChannel.component(forChannel: "ANE0") == .ane)
        #expect(EnergyChannel.component(forChannel: "DRAM0") == .ram)
        #expect(EnergyChannel.component(forChannel: "GPU SRAM0") == nil)
    }

    @Test func convertsUnitsToJoules() {
        #expect(EnergyChannel.joules(value: 2_000, unit: "mJ") == 2.0)
        #expect(EnergyChannel.joules(value: 3_000_000, unit: "uJ") == 3.0)
        #expect(EnergyChannel.joules(value: 4_000_000_000, unit: "nJ") == 4.0)
        #expect(EnergyChannel.joules(value: 1, unit: "furlongs") == nil)
    }
}

@Suite struct PowerReadingTests {
    @Test func packageTotalSumsOnlyComponentsThatCouldBeRead() {
        let power = PowerReading(cpu: nil, gpu: 0.5, ane: 0.25, ram: nil)

        #expect(power.packageTotal == 0.75)
    }

    @Test func headlinePowerPrefersSystemPowerOverPackageTotal() {
        let memory = MemoryReading(usedBytes: 1, totalBytes: 2, pressure: .normal)
        let power = PowerReading(cpu: nil, gpu: 0.5, ane: 0, ram: nil)
        let withSMC = Snapshot(timestamp: .distantPast, cpuUsage: 0, memory: memory, power: power, systemPower: 9)
        let withoutSMC = Snapshot(timestamp: .distantPast, cpuUsage: 0, memory: memory, power: power, systemPower: nil)

        #expect(withSMC.headlinePower == 9)
        #expect(withoutSMC.headlinePower == 0.5)
    }
}

@Suite struct FormatTests {
    private let snapshot = Snapshot(
        timestamp: Date(timeIntervalSince1970: 0),
        cpuUsage: 0.234,
        memory: MemoryReading(usedBytes: 8 * 1_073_741_824, totalBytes: 16 * 1_073_741_824, pressure: .normal),
        power: PowerReading(cpu: 2.2, gpu: 0.2, ane: 0, ram: 0.4),
        systemPower: 12.34
    )

    @Test func statusTitlePrefersSystemPower() {
        #expect(Format.statusTitle(snapshot, metrics: [.cpu, .power]) == "CPU 23% · Power 12.3W")
    }

    @Test func statusTitleListsSelectedMetricsInFixedOrder() {
        #expect(Format.statusTitle(snapshot, metrics: [.power, .memory, .cpu]) == "CPU 23% · RAM 8.0G · Power 12.3W")
        #expect(Format.statusTitle(snapshot, metrics: [.memory]) == "RAM 8.0G")
    }

    @Test func statusTitleIsPlaceholderWhenNothingSelected() {
        #expect(Format.statusTitle(snapshot, metrics: []) == "Sysbar")
    }

    @Test func metricsRoundTripThroughStoredStrings() {
        let stored = MenuBarMetric.storedValue(of: [.power, .cpu])

        #expect(MenuBarMetric.metrics(fromStored: stored) == [.cpu, .power])
        #expect(MenuBarMetric.metrics(fromStored: ["bogus"]) == MenuBarMetric.defaults)
        #expect(MenuBarMetric.metrics(fromStored: nil) == MenuBarMetric.defaults)
    }

    @Test func togglingNeverRemovesTheLastMetric() {
        #expect(MenuBarMetric.toggling(.cpu, in: [.cpu]) == [.cpu])
        #expect(MenuBarMetric.toggling(.cpu, in: [.cpu, .power]) == [.power])
        #expect(MenuBarMetric.toggling(.memory, in: [.cpu]) == [.cpu, .memory])
    }

    @Test func statusTitleFallsBackToPackagePower() {
        let noSMC = Snapshot(
            timestamp: snapshot.timestamp, cpuUsage: snapshot.cpuUsage,
            memory: snapshot.memory, power: snapshot.power, systemPower: nil
        )

        #expect(Format.statusTitle(noSMC, metrics: [.cpu, .power]) == "CPU 23% · Power 2.8W")
    }

    @Test func statusTitleOmitsPowerWhenUnavailable() {
        let none = Snapshot(
            timestamp: snapshot.timestamp, cpuUsage: snapshot.cpuUsage,
            memory: snapshot.memory, power: nil, systemPower: nil
        )

        #expect(Format.statusTitle(none, metrics: [.cpu, .power]) == "CPU 23%")
    }

    @Test func formatsGigabytesAndWatts() {
        #expect(Format.gigabytes(8 * 1_073_741_824) == "8.0 GB")
        #expect(Format.watts(4.123) == "4.1 W")
    }
}
