import Foundation
import Testing
@testable import SysbarCore

private let kib = 1_024.0
private let mib = 1_048_576.0
private let gib = 1_073_741_824.0

@Suite struct CounterRateTests {
    @Test func perSecondDividesDeltaByElapsedTime() {
        #expect(CounterRate.perSecond(previous: 1_000, current: 5_000, seconds: 2) == 2_000)
    }

    @Test func perSecondIsZeroWhenCounterWentBackwards() {
        #expect(CounterRate.perSecond(previous: 9, current: 3, seconds: 1) == 0)
    }

    @Test func perSecondIsZeroWhenNoTimeElapsed() {
        #expect(CounterRate.perSecond(previous: 1, current: 9, seconds: 0) == 0)
    }

    @Test func perSecond32SurvivesWraparound() {
        #expect(CounterRate.perSecond32(previous: UInt32.max - 9, current: 10, seconds: 1) == 20)
    }
}

@Suite struct RateFormatTests {
    @Test func scalesFromKilobytesToGigabytes() {
        #expect(Format.rate(0) == "0K")
        #expect(Format.rate(150 * kib) == "150K")
        #expect(Format.rate(1.2 * mib) == "1.2M")
        #expect(Format.rate(25 * mib) == "25M")
        #expect(Format.rate(1.5 * gib) == "1.5G")
    }

    @Test func memorySizesUseMegabytesBelowOneGigabyte() {
        #expect(Format.memory(340 * 1_048_576) == "340M")
        #expect(Format.memory(UInt64(1.5 * gib)) == "1.5G")
    }
}

@Suite struct GPUClientTests {
    @Test func parsesPidFromClientCreatorString() {
        #expect(GPUProbe.pid(fromClientCreator: "pid 373, logd") == 373)
        #expect(GPUProbe.pid(fromClientCreator: "nonsense") == nil)
    }
}

@Suite struct AppGroupingTests {
    @Test func nestedHelperGroupsUnderTheTopLevelApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/"
            + "Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

        #expect(AppGrouping.name(forExecutablePath: path, fallback: "x") == "Google Chrome")
    }

    @Test func plainExecutableUsesItsFileName() {
        #expect(AppGrouping.name(forExecutablePath: "/usr/sbin/cfprefsd", fallback: "x") == "cfprefsd")
    }

    @Test func emptyPathFallsBackToTheProcessName() {
        #expect(AppGrouping.name(forExecutablePath: "", fallback: "kernel_task") == "kernel_task")
    }
}

@Suite struct AppUsageTests {
    private func counters(
        _ group: String, cpu: UInt64 = 0, energy: UInt64 = 0, memory: UInt64 = 0, gpu: UInt64 = 0
    ) -> ProcessCounters {
        ProcessCounters(group: group, cpuNanoseconds: cpu, energyNanojoules: energy, footprintBytes: memory, gpuNanoseconds: gpu)
    }

    @Test func sumsRatesAcrossProcessesOfTheSameApp() {
        let previous: [Int32: ProcessCounters] = [1: counters("Chrome"), 2: counters("Chrome")]
        let current: [Int32: ProcessCounters] = [
            1: counters("Chrome", cpu: 1_000_000_000, energy: 3_000_000_000, memory: 100, gpu: 1_000_000_000),
            2: counters("Chrome", cpu: 500_000_000, energy: 1_000_000_000, memory: 50),
        ]

        let usage = AppUsageCalculator.usage(previous: previous, current: current, seconds: 2)

        #expect(usage == [AppUsage(name: "Chrome", cpu: 0.75, memoryBytes: 150, gpu: 0.5, powerWatts: 2)])
    }

    @Test func newProcessesReportMemoryButNoRates() {
        let usage = AppUsageCalculator.usage(
            previous: [:], current: [7: counters("Fresh", cpu: 9_000_000_000, memory: 10)], seconds: 2
        )

        #expect(usage == [AppUsage(name: "Fresh", cpu: 0, memoryBytes: 10, gpu: 0, powerWatts: 0)])
    }

    @Test func counterThatWentBackwardsCountsAsZero() {
        let usage = AppUsageCalculator.usage(
            previous: [7: counters("Reused", cpu: 5_000_000_000)], current: [7: counters("Reused", cpu: 1)], seconds: 1
        )

        #expect(usage.first?.cpu == 0)
    }

    @Test func topSortsDescendingByKeyThenNameAndHonoursLimit() {
        let apps = [
            AppUsage(name: "B", cpu: 0.5, memoryBytes: 10, gpu: 0, powerWatts: 1),
            AppUsage(name: "A", cpu: 0.5, memoryBytes: 30, gpu: 0, powerWatts: 3),
            AppUsage(name: "C", cpu: 0.9, memoryBytes: 20, gpu: 0, powerWatts: 2),
        ]

        #expect(AppUsageCalculator.top(apps, by: .cpu, limit: 3).map(\.name) == ["C", "A", "B"])
        #expect(AppUsageCalculator.top(apps, by: .memory, limit: 2).map(\.name) == ["A", "C"])
        #expect(AppUsageCalculator.top(apps, by: .power, limit: 1).map(\.name) == ["A"])
    }
}

@Suite struct ReadoutTests {
    private let snapshot = Snapshot(
        timestamp: Date(timeIntervalSince1970: 0),
        cpuUsage: 0.234,
        memory: MemoryReading(usedBytes: 8 * 1_073_741_824, totalBytes: 16 * 1_073_741_824, pressure: .normal),
        power: PowerReading(cpu: nil, gpu: 0.2, ane: 0, ram: nil),
        systemPower: 12.34,
        gpuUsage: 0.07,
        disk: IOThroughput(inbound: 2 * mib, outbound: 1 * mib),
        network: IOThroughput(inbound: 500 * kib, outbound: 100 * kib)
    )

    @Test func buildsOneReadoutPerSelectedMetricInTheGivenOrder() {
        let readouts = MenuBarReadouts.make(from: snapshot, metrics: MenuBarMetric.allCases.reversed())

        #expect(readouts.map(\.label) == ["Network", "Disk", "Power", "RAM", "GPU", "CPU"])
        #expect(readouts.map(\.text) == ["600K", "3.0M", "12.3W", "8.0G", "7%", "23%"])
    }

    @Test func levelsAreNormalisedToZeroThroughOne() {
        let readouts = MenuBarReadouts.make(from: snapshot, metrics: [.cpu, .memory, .power])

        #expect(readouts.map(\.level) == [0.234, 0.5, 12.34 / 30])
        #expect(MenuBarReadouts.rateLevel(0) == 0)
        #expect(MenuBarReadouts.rateLevel(10 * gib) == 1)
    }

    @Test func unavailableMetricsAreSkipped() {
        let bare = Snapshot(
            timestamp: snapshot.timestamp, cpuUsage: 0.5, memory: snapshot.memory, power: nil, systemPower: nil
        )

        let readouts = MenuBarReadouts.make(from: bare, metrics: MenuBarMetric.allCases)

        #expect(readouts.map(\.label) == ["CPU", "RAM"])
    }

    @Test func everyTextFitsItsReservedSlot() {
        let extreme = Snapshot(
            timestamp: snapshot.timestamp, cpuUsage: 1,
            memory: MemoryReading(usedBytes: 100 * 1_073_741_824, totalBytes: 128 * 1_073_741_824, pressure: .normal),
            power: nil, systemPower: 123.4, gpuUsage: 1,
            disk: IOThroughput(inbound: 900 * mib, outbound: 99 * mib),
            network: IOThroughput(inbound: 99 * gib, outbound: 0)
        )

        for readout in MenuBarReadouts.make(from: extreme, metrics: MenuBarMetric.allCases) {
            #expect(readout.text.count <= readout.slotCharacters, "\(readout.label): \(readout.text)")
        }
    }
}

@Suite struct MetricSelectionTests {
    @Test func newMetricsKeepDisplayOrderWhenToggledOn() {
        #expect(MenuBarMetric.toggling(.gpu, in: [.cpu, .memory]) == [.cpu, .gpu, .memory])
        #expect(MenuBarMetric.toggling(.network, in: [.cpu]) == [.cpu, .network])
    }
}
