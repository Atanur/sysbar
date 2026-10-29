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

    @Test func compactMemoryUsesGigabytesFromOneHundredMegabytes() {
        #expect(Format.memory(25 * 1_048_576) == "25M")
        #expect(Format.memory(99 * 1_048_576) == "99M")
        #expect(Format.memory(100 * 1_048_576) == "0.1G")
        #expect(Format.memory(340 * 1_048_576) == "0.3G")
        #expect(Format.memory(383 * 1_048_576) == "0.4G")
        #expect(Format.memory(499 * 1_048_576) == "0.5G")
        #expect(Format.memory(500 * 1_048_576) == "0.5G")
        #expect(Format.memory(700 * 1_048_576) == "0.7G")
        #expect(Format.memory(999 * 1_048_576) == "1.0G")
        #expect(Format.memory(1_000 * 1_048_576) == "1.0G")
        #expect(Format.memory(1_023 * 1_048_576) == "1.0G")
        #expect(Format.memory(UInt64(1.5 * gib)) == "1.5G")
        #expect(Format.memory(UInt64(11.2 * gib)) == "11G")
    }

    @Test func detailedMemoryWaitsUntilOneThousandMegabytes() {
        #expect(Format.memory(340 * 1_048_576, compact: false) == "340M")
        #expect(Format.memory(700 * 1_048_576, compact: false) == "700M")
        #expect(Format.memory(999 * 1_048_576, compact: false) == "999M")
        #expect(Format.memory(1_000 * 1_048_576, compact: false) == "1.0G")
        #expect(Format.memory(UInt64(1.5 * gib), compact: false) == "1.5G")
    }

    @Test func appPowerKeepsTheColumnShort() {
        #expect(Format.compactPower(0.004) == "–")
        #expect(Format.compactPower(0.005) == "5mW")
        #expect(Format.compactPower(0.038) == "38mW")
        #expect(Format.compactPower(0.099) == "99mW")
        #expect(Format.compactPower(0.1) == "0.1W")
        #expect(Format.compactPower(0.15) == "0.2W")
        #expect(Format.compactPower(0.743) == "0.7W")
        #expect(Format.compactPower(0.995) == "1.0W")
        #expect(Format.compactPower(1.2) == "1.2W")
        #expect(Format.compactPower(12.34) == "12.3W")
        #expect(Format.compactPower(100) == "100W")
    }

    @Test func detailedPowerKeepsMilliwattsWhenThereIsRoom() {
        #expect(Format.detailedPower(0.004) == "–")
        #expect(Format.detailedPower(0.038) == "38mW")
        #expect(Format.detailedPower(0.15) == "150mW")
        #expect(Format.detailedPower(0.743) == "743mW")
        #expect(Format.detailedPower(1.2) == "1.2W")
    }

    @Test func appCPUSharesKeepOneDecimalBelowTenPercent() {
        #expect(Format.finePercent(0.036, separator: ".") == "3.6%")
        #expect(Format.finePercent(0, separator: ".") == "0.0%")
        #expect(Format.finePercent(0.0996, separator: ".") == "10%")
        #expect(Format.finePercent(0.234, separator: ".") == "23%")
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
        _ group: String, cpu: UInt64 = 0, energy: UInt64 = 0, memory: UInt64 = 0, gpu: UInt64 = 0,
        network: ByteCounters? = nil, networkIsNew: Bool = false
    ) -> ProcessCounters {
        ProcessCounters(
            group: group, cpuNanoseconds: cpu, energyNanojoules: energy, footprintBytes: memory,
            gpuNanoseconds: gpu, network: network, networkIsNew: networkIsNew
        )
    }

    @Test func sumsRatesAcrossProcessesOfTheSameApp() {
        let previous: [Int32: ProcessCounters] = [1: counters("Chrome"), 2: counters("Chrome")]
        let current: [Int32: ProcessCounters] = [
            1: counters("Chrome", cpu: 1_000_000_000, energy: 3_000_000_000, memory: 100, gpu: 1_000_000_000),
            2: counters("Chrome", cpu: 500_000_000, energy: 1_000_000_000, memory: 50),
        ]

        let usage = AppUsageCalculator.usage(previous: previous, current: current, seconds: 2, cores: 1)

        #expect(usage == [AppUsage(name: "Chrome", cpu: 0.75, memoryBytes: 150, gpu: 0.5, powerWatts: 2)])
    }

    @Test func cpuIsAShareOfTheWholeMacLikeTheCPUCard() {
        // Two cores' worth of work on an eight-core Mac is a quarter of it.
        let usage = AppUsageCalculator.usage(
            previous: [1: counters("Xcode")], current: [1: counters("Xcode", cpu: 4_000_000_000)], seconds: 2, cores: 8
        )

        #expect(usage.first?.cpu == 0.25)
    }

    @Test func newProcessesReportMemoryButNoRates() {
        let usage = AppUsageCalculator.usage(
            previous: [:], current: [7: counters("Fresh", cpu: 9_000_000_000, memory: 10)], seconds: 2, cores: 1
        )

        #expect(usage == [AppUsage(name: "Fresh", cpu: 0, memoryBytes: 10, gpu: 0, powerWatts: 0)])
    }

    @Test func counterThatWentBackwardsCountsAsZero() {
        let usage = AppUsageCalculator.usage(
            previous: [7: counters("Reused", cpu: 5_000_000_000)], current: [7: counters("Reused", cpu: 1)], seconds: 1, cores: 1
        )

        #expect(usage.first?.cpu == 0)
    }

    @Test func sumsNetworkRatesAcrossProcessesOfTheSameApp() {
        let previous: [Int32: ProcessCounters] = [
            1: counters("Chrome", network: ByteCounters(received: 1_000, sent: 2_000)),
            2: counters("Chrome", network: ByteCounters(received: 0, sent: 0)),
        ]
        let current: [Int32: ProcessCounters] = [
            1: counters("Chrome", network: ByteCounters(received: 3_000, sent: 4_000)),
            2: counters("Chrome", network: ByteCounters(received: 1_000, sent: 1_000)),
        ]

        let usage = AppUsageCalculator.usage(previous: previous, current: current, seconds: 2, cores: 1)

        #expect(usage.first?.networkInbound == 1_500)
        #expect(usage.first?.networkOutbound == 1_500)
        #expect(usage.first?.networkTotal == 3_000)
    }

    @Test func aNewProcessStartsWithZeroNetworkRate() {
        let usage = AppUsageCalculator.usage(
            previous: [:],
            current: [7: counters("Fresh", network: ByteCounters(received: 9_000, sent: 3_000))],
            seconds: 2, cores: 1
        )

        #expect(usage.first?.networkInbound == 0)
        #expect(usage.first?.networkOutbound == 0)
    }

    @Test func aProcessesFirstNetworkReadingIsABaselineNotASpike() {
        // The process had no sockets in the previous sample, so its counter was zero. Its first
        // reported counter includes everything since it started; that must not become one rate.
        let usage = AppUsageCalculator.usage(
            previous: [7: counters("Safari", network: ByteCounters(received: 0, sent: 0))],
            current: [
                7: counters(
                    "Safari", network: ByteCounters(received: 5_000_000, sent: 1_000), networkIsNew: true
                )
            ],
            seconds: 1, cores: 1
        )

        #expect(usage.first?.networkInbound == 0)
        #expect(usage.first?.networkOutbound == 0)
    }

    @Test func networkStaysUnknownWhenNettopCouldNotBeRead() {
        let usage = AppUsageCalculator.usage(
            previous: [7: counters("Safari")], current: [7: counters("Safari")], seconds: 2, cores: 1
        )

        #expect(usage.first?.networkInbound == nil)
        #expect(usage.first?.networkTotal == nil)
    }

    @Test func networkCounterThatWentBackwardsCountsAsZero() {
        let usage = AppUsageCalculator.usage(
            previous: [7: counters("Safari", network: ByteCounters(received: 9_000, sent: 3_000))],
            current: [7: counters("Safari", network: ByteCounters(received: 10, sent: 5))],
            seconds: 1, cores: 1
        )

        #expect(usage.first?.networkInbound == 0)
        #expect(usage.first?.networkOutbound == 0)
    }

    @Test func topSortsDescendingByKeyThenNameAndHonoursLimit() {
        let apps = [
            AppUsage(name: "B", cpu: 0.5, memoryBytes: 10, gpu: 0, powerWatts: 1),
            AppUsage(name: "A", cpu: 0.5, memoryBytes: 30, gpu: 0, powerWatts: 3),
            AppUsage(name: "C", cpu: 0.9, memoryBytes: 20, gpu: 0, powerWatts: 2),
            AppUsage(
                name: "D", cpu: 0.1, memoryBytes: 15, gpu: 0, powerWatts: 0,
                networkInbound: 600, networkOutbound: 400
            ),
        ]

        #expect(AppUsageCalculator.top(apps, by: .cpu, limit: 3).map(\.name) == ["C", "A", "B"])
        #expect(AppUsageCalculator.top(apps, by: .memory, limit: 2).map(\.name) == ["A", "C"])
        #expect(AppUsageCalculator.top(apps, by: .power, limit: 1).map(\.name) == ["A"])
        #expect(AppUsageCalculator.top(apps, by: .network, limit: 2).map(\.name) == ["D", "A"])
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
