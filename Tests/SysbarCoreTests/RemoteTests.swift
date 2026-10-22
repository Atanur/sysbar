import Foundation
import Testing
@testable import SysbarCore

private let linuxOutput = """
os=Linux
cores=4
cpu=1000 20 300 5000 100 0 10 0
mem=8000000 6000000
load=0.52 0.40 0.35
uptime=93784.12
net=1500000 600000
disk=2000000 1000000
gpu=37
proc=12.5 20480 nginx
proc=3.1 102400 postgres: writer
"""

private let linuxOutputLater = """
os=Linux
cores=4
cpu=1100 20 400 5300 100 0 10 0
mem=8000000 6000000
load=0.60 0.42 0.36
uptime=93786.12
net=1502000 604000
disk=2004000 1010000
"""

private let macOutput = """
os=Darwin
cores=10
cpuline=CPU usage: 5.26% user, 8.77% sys, 85.96% idle
memtotal=17179869184
vm=Mach Virtual Memory Statistics: (page size of 16384 bytes)
vm=Pages free:                               12345.
vm=Anonymous pages:                         180000.
vm=Pages purgeable:                          10000.
vm=Pages wired down:                         90000.
vm=Pages occupied by compressor:             60000.
load=1.23 1.45 1.67
boottime=1700000000
now=1700003600
net=9000 3000
proc=8.2 512000 Google Chrome Helper
proc=5.0 204800 WindowServer
proc=1.0 3000 ps
"""

@Suite struct RemoteParserTests {
    @Test func parsesLinuxOutput() throws {
        let raw = try #require(RemoteMetricsParser.parse(linuxOutput))

        #expect(raw.os == .linux)
        #expect(raw.cores == 4)
        #expect(raw.linuxTicks == LinuxCPUTicks(busy: 1000 + 20 + 300 + 0 + 10 + 0, idle: 5000 + 100))
        #expect(raw.memoryTotalBytes == 8_000_000 * 1_024)
        #expect(raw.memoryUsedBytes == 2_000_000 * 1_024)
        #expect(raw.load == LoadAverage(one: 0.52, five: 0.40, fifteen: 0.35))
        #expect(raw.uptime == 93_784.12)
        #expect(raw.network == ByteCounters(received: 1_500_000, sent: 600_000))
        #expect(raw.disk == ByteCounters(received: 2_000_000, sent: 1_000_000))
        #expect(raw.gpuUsage == 0.37)
        #expect(raw.processes == [
            RemoteProcess(name: "nginx", cpu: 0.125, memoryBytes: 20_480 * 1_024),
            RemoteProcess(name: "postgres: writer", cpu: 0.031, memoryBytes: 102_400 * 1_024),
        ])
    }

    @Test func parsesMacOutput() throws {
        let raw = try #require(RemoteMetricsParser.parse(macOutput))

        #expect(raw.os == .macOS)
        #expect(raw.cores == 10)
        #expect(raw.directCPUUsage == (100 - 85.96) / 100)
        #expect(raw.memoryTotalBytes == 17_179_869_184)
        // (anonymous - purgeable + wired + compressor) pages of 16 KiB
        #expect(raw.memoryUsedBytes == UInt64(180_000 - 10_000 + 90_000 + 60_000) * 16_384)
        #expect(raw.load == LoadAverage(one: 1.23, five: 1.45, fifteen: 1.67))
        #expect(raw.uptime == 3_600)
        #expect(raw.network == ByteCounters(received: 9_000, sent: 3_000))
        #expect(raw.disk == nil)
        let first = try #require(raw.processes.first)
        #expect(first.name == "Google Chrome Helper")
        #expect(abs(first.cpu - 0.082) < 1e-9)
        #expect(first.memoryBytes == 512_000 * 1_024)
        #expect(raw.processes.map(\.name) == ["Google Chrome Helper", "WindowServer"], "the script's own tools are hidden")
    }

    @Test func outputWithoutAnOsLineIsRejected() {
        #expect(RemoteMetricsParser.parse("") == nil)
        #expect(RemoteMetricsParser.parse("garbage\nmore garbage") == nil)
    }

    @Test func unreadableFieldsBecomeNilInsteadOfFailingTheWholeSample() throws {
        let raw = try #require(RemoteMetricsParser.parse("os=Linux\ncores=two\nmem=abc def\nload=x"))

        #expect(raw.cores == 0)
        #expect(raw.memoryTotalBytes == nil)
        #expect(raw.load == nil)
    }
}

@Suite struct RemoteTrackerTests {
    @Test func linuxRatesComeFromTheDifferenceBetweenTwoSamples() throws {
        var tracker = RemoteTracker()
        let first = tracker.ingest(try #require(RemoteMetricsParser.parse(linuxOutput)), atNanos: 0, date: .distantPast)
        let second = tracker.ingest(
            try #require(RemoteMetricsParser.parse(linuxOutputLater)), atNanos: 2_000_000_000, date: .distantPast
        )

        #expect(first.cpuUsage == nil)
        #expect(first.network == nil)
        // busy +200 (100 user + 100 system), idle +300
        #expect(second.cpuUsage == 0.4)
        #expect(second.network == IOThroughput(inbound: 1_000, outbound: 2_000))
        #expect(second.disk == IOThroughput(inbound: 2_000, outbound: 5_000))
        #expect(second.memory?.usedBytes == 2_000_000 * 1_024)
    }

    @Test func macCpuNeedsNoBaseline() throws {
        var tracker = RemoteTracker()

        let snapshot = tracker.ingest(try #require(RemoteMetricsParser.parse(macOutput)), atNanos: 0, date: .distantPast)

        #expect(snapshot.cpuUsage == (100 - 85.96) / 100)
        #expect(snapshot.memory?.totalBytes == 17_179_869_184)
        #expect(snapshot.load?.one == 1.23)
    }

    @Test func loadPerCoreDrivesTheLoadLevel() throws {
        var tracker = RemoteTracker()
        let snapshot = tracker.ingest(try #require(RemoteMetricsParser.parse(macOutput)), atNanos: 0, date: .distantPast)

        #expect(snapshot.loadFraction == 1.23 / 10)
    }
}

@Suite struct SSHCommandTests {
    private func device(
        host: String = "vps.example.com", user: String = "", port: Int? = nil, identity: String = ""
    ) -> RemoteDevice {
        RemoteDevice(id: UUID(), name: "VPS", host: host, user: user, port: port, identityFile: identity)
    }

    @Test func alwaysRunsNonInteractivelyAndReadsTheScriptFromStandardInput() {
        let args = SSHCommand.arguments(for: device(), controlPath: "/tmp/mm-%C")

        #expect(args.contains("BatchMode=yes"))
        #expect(args.contains("ControlPath=/tmp/mm-%C"))
        #expect(args.suffix(4) == ["--", "vps.example.com", "sh", "-s"])
        #expect(!args.contains("-p"))
        #expect(!args.contains("-l"))
        #expect(!args.contains("-i"))
    }

    @Test func addsPortUserAndIdentityOnlyWhenSet() {
        let args = SSHCommand.arguments(
            for: device(user: "root", port: 2222, identity: "/Users/me/.ssh/id_ed25519"), controlPath: "/tmp/mm-%C"
        )

        #expect(args.joined(separator: " ").contains("-p 2222"))
        #expect(args.joined(separator: " ").contains("-l root"))
        #expect(args.joined(separator: " ").contains("-i /Users/me/.ssh/id_ed25519"))
        #expect(args.contains("IdentitiesOnly=yes"))
    }

    @Test func theSharedConnectionOutlivesASingleSampleSoReopeningDoesNotLogInAgain() {
        let args = SSHCommand.arguments(for: device(), controlPath: "/tmp/mm-%C")

        #expect(SSHCommand.keepAliveSeconds >= 30)
        #expect(args.contains("ControlPersist=\(SSHCommand.keepAliveSeconds)"))
    }

    @Test func extraOptionsGoBeforeTheHostSeparator() {
        let args = SSHCommand.arguments(
            for: device(), controlPath: "/tmp/mm-%C", extraOptions: ["-o", "UserKnownHostsFile=/tmp/kh"]
        )

        #expect(args.contains("UserKnownHostsFile=/tmp/kh"))
        #expect(args.firstIndex(of: "UserKnownHostsFile=/tmp/kh")! < args.firstIndex(of: "--")!)
        #expect(args.suffix(4) == ["--", "vps.example.com", "sh", "-s"])
    }

    @Test func closingTheSharedConnectionUsesTheSameControlPathAndEndpoint() {
        let args = SSHCommand.exitArguments(for: device(user: "root", port: 2222), controlPath: "/tmp/mm-%C")

        #expect(Array(args.prefix(2)) == ["-O", "exit"])
        #expect(args.contains("ControlPath=/tmp/mm-%C"))
        #expect(args.joined(separator: " ").contains("-p 2222"))
        #expect(args.joined(separator: " ").contains("-l root"))
        #expect(args.suffix(2) == ["--", "vps.example.com"])
    }

    @Test func expandsTildeInTheIdentityPath() {
        let args = SSHCommand.arguments(for: device(identity: "~/.ssh/key"), controlPath: "/tmp/mm-%C")

        let path = args[args.firstIndex(of: "-i")! + 1]
        #expect(path == NSString(string: "~/.ssh/key").expandingTildeInPath)
        #expect(!path.hasPrefix("~"))
    }
}

@Suite struct SSHFailureTests {
    @Test func explainsTheCommonFailuresInPlainTurkish() {
        func message(_ stderr: String) -> String { SSHFailure.message(stderr: stderr, exitCode: 255, host: "vps") }

        #expect(message("root@vps: Permission denied (publickey).").contains("Passwords are not supported"))
        #expect(message("Host key verification failed.").contains("ssh vps"))
        #expect(message("@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@").contains("has changed"))
        #expect(message("ssh: Could not resolve hostname vps: nodename nor servname").contains("could not be resolved"))
        #expect(message("ssh: connect to host vps port 22: Connection refused").contains("refused"))
        #expect(message("ssh: connect to host vps port 22: Operation timed out").contains("timed out"))
        #expect(message("ssh: connect to host vps port 22: No route to host").contains("unreachable"))
    }

    @Test func unknownErrorsShowTheLastLineOrTheExitCode() {
        #expect(SSHFailure.message(stderr: "first\nsomething odd\n", exitCode: 1, host: "h") == "something odd")
        #expect(SSHFailure.message(stderr: "", exitCode: 7, host: "h") == "Unknown error (code 7).")
    }
}

@Suite struct RemoteDeviceValidationTests {
    private func device(
        name: String = "VPS", host: String = "vps.example.com", user: String = "root",
        port: Int? = nil, identity: String = ""
    ) -> RemoteDevice {
        RemoteDevice(id: UUID(), name: name, host: host, user: user, port: port, identityFile: identity)
    }

    @Test func acceptsATypicalDevice() {
        #expect(device(port: 22, identity: "~/.ssh/id_ed25519").problems.isEmpty)
        #expect(device(host: "192.168.1.20", user: "").problems.isEmpty)
        #expect(device(host: "my-mac.local").problems.isEmpty)
    }

    @Test func rejectsValuesThatCouldBeReadAsSshOptions() {
        #expect(device(host: "-oProxyCommand=evil").problems == [.invalidHost])
        #expect(device(user: "-oProxyCommand=evil").problems == [.invalidUser])
        #expect(device(host: "a b").problems == [.invalidHost])
        #expect(device(host: "").problems == [.invalidHost])
    }

    @Test func rejectsBadNamePortAndIdentity() {
        #expect(device(name: "  ").problems == [.emptyName])
        #expect(device(port: 0).problems == [.invalidPort])
        #expect(device(port: 70_000).problems == [.invalidPort])
        #expect(device(identity: "relative/key").problems == [.invalidIdentityFile])
        #expect(device(identity: "/key\nwith newline").problems == [.invalidIdentityFile])
    }
}

@Suite struct RemoteCardTests {
    @Test func devicesStoredBeforeCardChoiceExistedShowEveryCard() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"VPS","host":"vps","user":"","identityFile":""}"#

        let device = try JSONDecoder().decode(RemoteDevice.self, from: Data(json.utf8))

        #expect(device.cards == RemoteCard.allCases)
        #expect(device.interval == SamplingInterval.remoteDefaultSeconds)
    }

    @Test func eachDeviceKeepsItsOwnIntervalWithinTheAllowedRange() throws {
        let device = RemoteDevice(name: "VPS", host: "vps", user: "", port: nil, identityFile: "", interval: 12)
        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(device))
        let tampered = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"VPS","host":"vps","user":"","identityFile":"","interval":0.01}"#

        #expect(decoded.interval == 12)
        #expect(try JSONDecoder().decode(RemoteDevice.self, from: Data(tampered.utf8)).interval == 2)
    }

    @Test func aChosenSubsetSurvivesEncodingAndDecoding() throws {
        let device = RemoteDevice(
            name: "VPS", host: "vps", user: "", port: nil, identityFile: "", cards: [.cpu, .network]
        )

        let decoded = try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(device))

        #expect(decoded == device)
        #expect(decoded.cards == [.cpu, .network])
    }

    @Test func newDevicesShowEveryCardAndMayHideThemAll() {
        let device = RemoteDevice(name: "VPS", host: "vps", user: "", port: nil, identityFile: "")

        #expect(device.cards == RemoteCard.allCases)
        #expect(OrderedSelection.toggling(RemoteCard.cpu, in: [.cpu], minimum: 0) == [])
    }

    @Test func visibleCardsAreChosenAndAvailableInDeclaredOrder() {
        let visible = RemoteCard.visible(chosen: [.gpu, .disk, .cpu], available: [.cpu, .memory, .gpu])

        #expect(visible == [.cpu, .gpu])
    }

    @Test func diskAndGpuAreAvailableOnlyWhenTheServerReportsThem() throws {
        var linuxTracker = RemoteTracker()
        var macTracker = RemoteTracker()
        let linux = linuxTracker.ingest(try #require(RemoteMetricsParser.parse(linuxOutput)), atNanos: 0, date: .distantPast)
        let mac = macTracker.ingest(try #require(RemoteMetricsParser.parse(macOutput)), atNanos: 0, date: .distantPast)

        // Disk is reported on the very first sample even though its rate needs a second one.
        #expect(RemoteCard.available(in: [linux]) == RemoteCard.allCases)
        #expect(RemoteCard.available(in: [mac]) == [.cpu, .memory, .load, .network])
    }
}

@Suite struct OrderedSelectionTests {
    @Test func appColumnsFollowTheSameRulesAsMenuBarMetrics() {
        #expect(OrderedSelection.toggling(AppSortKey.gpu, in: [AppSortKey.cpu], minimum: 1) == [.cpu, .gpu])
        #expect(OrderedSelection.toggling(AppSortKey.cpu, in: [AppSortKey.cpu], minimum: 1) == [.cpu])
        #expect(OrderedSelection.ordered(fromStored: ["power", "cpu", "bogus"]) as [AppSortKey]? == [.cpu, .power])
        #expect(OrderedSelection.storedValue(of: [AppSortKey.memory, .gpu]) == ["memory", "gpu"])
    }
}

@Suite struct RemoteTemperatureTests {
    @Test func readsMillidegreesAndIgnoresNonsense() throws {
        #expect(try #require(RemoteMetricsParser.parse("os=Linux\ntemp=54000")).cpuTemperature == 54)
        #expect(try #require(RemoteMetricsParser.parse("os=Linux\ntemp=61")).cpuTemperature == 61)
        #expect(try #require(RemoteMetricsParser.parse("os=Linux\ntemp=-3000")).cpuTemperature == nil)
        #expect(try #require(RemoteMetricsParser.parse("os=Linux")).cpuTemperature == nil)
    }
}
