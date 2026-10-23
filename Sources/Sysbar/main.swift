import AppKit
import Foundation
import SysbarCore

// `Sysbar --open-details METRIC` does what clicking that metric's card does (opens Activity Monitor
// on its tab, or Battery settings) and prints the target. METRIC is cpu, gpu, memory, power, disk or network.
if let flag = CommandLine.arguments.firstIndex(of: "--open-details"),
   flag + 1 < CommandLine.arguments.count,
   let metric = MenuBarMetric(rawValue: CommandLine.arguments[flag + 1]) {
    let target = SystemLinks.target(for: metric, hasBattery: BatteryProbe.read() != nil)
    print("target:", target)
    SystemLinks.open(target)
    Thread.sleep(forTimeInterval: 1)
    exit(0)
}

// `Sysbar --l10n-sample` prints a few strings in the current language, to check that the bundled
// translations load. Combine with `-AppleLanguages '(tr)'` to try a language.
if CommandLine.arguments.contains("--l10n-sample") {
    print(L("Top apps"), "|", L("Quit Sysbar"), "|", Format.uptime(93_784), "|", L("charging"))
    print(Format.compactGigabytes(11_703_000_000), "|", Format.watts(7.24), "|", Format.rate(1_300_000), "|", MenuBarMetric.power.widestText)
    exit(0)
}

// `Sysbar --render-menubar PATH` draws the menu bar readout with the battery at several charges, in
// light and dark and with and without colour, and writes it as a PNG, to check the drawing by eye.
if let flag = CommandLine.arguments.firstIndex(of: "--render-menubar"), flag + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        func image(charge: Double, colored: Bool) -> NSImage {
            let battery = BatteryInfo(
                fraction: charge, isPluggedIn: false, isCharging: false, isFull: false, minutesRemaining: nil,
                cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
            )
            let snapshot = Snapshot(
                timestamp: Date(), cpuUsage: 0.23,
                memory: MemoryReading(usedBytes: 10_900_000_000, totalBytes: 17_179_869_184, pressure: .normal),
                power: nil, systemPower: 7.2, battery: battery
            )
            let readouts = MenuBarReadouts.make(from: snapshot, metrics: [.cpu, .memory], batteryThreshold: 100)
            // The lowest charge also shows the heat warning, to check how it is drawn.
            return MenuBarImage.make(readouts, colored: colored, alert: charge < 0.2 ? .critical : nil)
        }
        let charges = [0.92, 0.45, 0.3, 0.12]
        let rows: [(NSAppearance.Name, Bool)] = [(.aqua, false), (.aqua, true), (.darkAqua, false), (.darkAqua, true)]
        let rowHeight: CGFloat = 26
        let gap: CGFloat = 24
        let width = charges.map { image(charge: $0, colored: false).size.width + gap }.reduce(gap, +)
        let height = rowHeight * CGFloat(rows.count)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        canvas.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
        for (index, (name, colored)) in rows.enumerated() {
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                let y = rowHeight * CGFloat(rows.count - 1 - index)
                NSColor(white: name == .darkAqua ? 0.16 : 0.93, alpha: 1).setFill()
                NSRect(x: 0, y: y, width: width, height: rowHeight).fill()
                var x = gap
                for charge in charges {
                    let picture = image(charge: charge, colored: colored)
                    picture.draw(in: NSRect(x: x, y: y + 2, width: picture.size.width, height: picture.size.height))
                    x += picture.size.width + gap
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
        try? canvas.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote", url.path)
    }
    exit(0)
}

// `Sysbar --remote-script` prints the script sent to remote machines; `Sysbar --parse-remote`
// reads that script's output from standard input and prints what the parser makes of it.
if CommandLine.arguments.contains("--remote-script") {
    print(RemoteScript.source)
    exit(0)
}
if CommandLine.arguments.contains("--parse-remote") {
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    if let sample = RemoteMetricsParser.parse(input) {
        dump(sample)
    } else {
        print("parse failed")
    }
    exit(0)
}

// `Sysbar --remote-test HOST [USER [PORT [IDENTITY [KNOWN_HOSTS]]]]` samples a remote machine twice over ssh,
// exactly as the app does, and prints what it read. It is how the ssh path is verified end to end.
if let flag = CommandLine.arguments.firstIndex(of: "--remote-test") {
    let arguments = Array(CommandLine.arguments.dropFirst(flag + 1))
    func argument(_ index: Int) -> String { index < arguments.count ? arguments[index] : "" }
    let device = RemoteDevice(
        name: "test", host: argument(0), user: argument(1), port: Int(argument(2)), identityFile: argument(3)
    )
    guard device.problems.isEmpty else {
        print("invalid device:", device.problems)
        exit(2)
    }
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        let knownHosts = argument(4)
        let runner = SSHRunner(extraOptions: knownHosts.isEmpty ? [] : ["-o", "UserKnownHostsFile=\(knownHosts)"])
        var tracker = RemoteTracker()
        for round in 1...2 {
            switch await runner.run(device) {
            case .failure(let error):
                print("round \(round) failed:", error.message)
                exit(1)
            case .success(let output):
                guard let raw = RemoteMetricsParser.parse(output) else {
                    print("round \(round): unparseable output")
                    exit(1)
                }
                let snapshot = tracker.ingest(raw, atNanos: clock_gettime_nsec_np(CLOCK_UPTIME_RAW), date: Date())
                print("round \(round): os=\(snapshot.os) cores=\(snapshot.cores)",
                      "cpu=\(snapshot.cpuUsage.map(Format.percent) ?? "-")",
                      "mem=\(snapshot.memory.map { Format.gigabytes($0.usedBytes) } ?? "-")",
                      "load=\(snapshot.load?.one ?? -1)",
                      "net=\(snapshot.network.map { Format.rate($0.total) } ?? "-")",
                      "uptime=\(snapshot.uptime.map(Format.uptime) ?? "-")",
                      "procs=\(snapshot.processes.prefix(3).map(\.name))")
            }
            if round == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        // Passing "keep" as the sixth argument leaves the connection to expire by itself, as the app does.
        if argument(5) != "keep" { runner.closeConnectionNow(device) }
        finished.signal()
    }
    finished.wait()
    exit(0)
}

// `Sysbar --smc-keys=PREFIX` lists every readable float SMC key starting with PREFIX, e.g. "Tp".
if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--smc-keys=") }) {
    SystemPower.floatKeys(prefix: String(flag.dropFirst("--smc-keys=".count))).forEach { print($0.key, $0.value) }
    exit(0)
}

// `Sysbar --smc-raw=KEY,KEY` prints each key's four-character type and raw bytes (read only).
if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--smc-raw=") }) {
    for key in flag.dropFirst("--smc-raw=".count).split(separator: ",").map(String.init) {
        guard let value = SystemPower.rawValue(key) else {
            print(key, "unreadable")
            continue
        }
        print(key, "'\(value.type)'", value.bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
    }
    exit(0)
}

// `Sysbar --smc-log=N` prints one CSV row per second for N seconds: epoch, then every SMC "P*" float key.
// Used to correlate SMC keys with `powermetrics` readings.
if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--smc-log=") }) {
    let seconds = Int(flag.dropFirst("--smc-log=".count)) ?? 30
    for tick in 0..<seconds {
        let keys = SystemPower.floatKeys(prefix: "P")
        if tick == 0 { print("epoch," + keys.map(\.key).joined(separator: ",")) }
        print("\(Int(Date().timeIntervalSince1970))," + keys.map { String($0.value) }.joined(separator: ","))
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1)
    }
    exit(0)
}

// `Sysbar --probe` prints raw readings once and exits; handy for verifying sensors.
if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--probe") }) {
    let seconds = Double(flag.dropFirst("--probe=".count)) ?? 1
    let sampler = SystemSampler()
    sampler.prime()
    Thread.sleep(forTimeInterval: seconds)
    print("IOReport energy channels (\(seconds) s interval):")
    sampler.describeEnergyChannels().forEach { print("  \($0)") }
    let snapshot = sampler.sample()
    print("cpu:", Format.percent(snapshot.cpuUsage))
    if let thermal = snapshot.thermal {
        let parts = ThermalSource.allCases.compactMap { source in thermal.celsius(source).map { "\(source.rawValue) \(Int($0.rounded()))°" } }
        print("temperatures:", parts.joined(separator: " · "), "· pressure \(thermal.pressure)")
        thermal.fans.forEach { print("  fan \($0.index): \(Int($0.rpm)) rpm of \(Int($0.minimum))–\(Int($0.maximum)) (\(Format.percent($0.fraction)))") }
        if let assessment = ThermalAssessment.assess([snapshot]) {
            print("assessment:", assessment.cause, "·", assessment.source, Int(assessment.celsius.rounded()), "·", assessment.level)
        }
    }
    print("memory:", Format.gigabytes(snapshot.memory.usedBytes), "/", Format.gigabytes(snapshot.memory.totalBytes), snapshot.memory.pressure)
    print("package power:", snapshot.power.map { "\($0)" } ?? "unavailable")
    print("system power (SMC PSTR):", snapshot.systemPower.map { Format.watts($0) } ?? "unavailable")
    let costStart = ContinuousClock.now
    for _ in 0..<50 { _ = sampler.sample() }
    print("average cost of one sample:", (ContinuousClock.now - costStart) / 50)
    print("gpu:", snapshot.gpuUsage.map(Format.percent) ?? "unavailable")
    print("disk:", snapshot.disk.map { "read \(Format.rate($0.inbound)) write \(Format.rate($0.outbound))" } ?? "unavailable")
    print("network:", snapshot.network.map { "down \(Format.rate($0.inbound)) up \(Format.rate($0.outbound))" } ?? "unavailable")

    let processes = ProcessSampler()
    processes.prime()
    Thread.sleep(forTimeInterval: 2)
    let scanStart = ContinuousClock.now
    let apps = processes.sample()
    print("process scan:", ContinuousClock.now - scanStart)
    print("apps seen:", apps.count)
    print(String(format: "all apps: cpu %.1f cores, power %.2f W", apps.map(\.cpu).reduce(0, +), apps.map(\.powerWatts).reduce(0, +)))
    for key in AppSortKey.allCases {
        print("top by \(key):")
        AppUsageCalculator.top(apps, by: key, limit: 5).forEach {
            print(String(format: "  %-28@ cpu %5.1f%%  mem %@  gpu %4.1f%%  power %.2f W",
                         $0.name as NSString, $0.cpu * 100, Format.memory($0.memoryBytes), $0.gpu * 100, $0.powerWatts))
        }
    }

    print("SMC float keys starting with P:")
    SystemPower.floatKeys(prefix: "P").forEach { print("  \($0.key) = \($0.value)") }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
