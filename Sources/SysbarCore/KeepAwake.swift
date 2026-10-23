import Foundation

/// How long the Mac is kept awake with its lid closed.
public enum KeepAwakeDuration: CaseIterable, Sendable {
    case oneHour
    case fourHours
    case untilOff

    /// Nil for `untilOff`, which has no end.
    public var seconds: TimeInterval? {
        switch self {
        case .oneHour: 3_600
        case .fourHours: 14_400
        case .untilOff: nil
        }
    }

    public func endDate(from start: Date) -> Date? {
        seconds.map { start.addingTimeInterval($0) }
    }
}

public enum KeepAwakeStop: Equatable, Sendable {
    case timeUp
    case lowBattery
    /// The app it was kept awake for was closed.
    case appQuit
}

/// When keeping the Mac awake ends by itself. A closed lid in a bag is the risk, so a low
/// battery ends it too; plugged in, the charge does not matter.
public enum KeepAwakePolicy {
    /// Charge, in percent, at or below which it ends while the Mac runs on battery.
    public static let lowBatteryPercent = 20

    public static func stopReason(now: Date, endsAt: Date?, battery: BatteryInfo?) -> KeepAwakeStop? {
        if let endsAt, now >= endsAt { return .timeUp }
        if let battery, !battery.isPluggedIn, BatteryMenuBar.percent(battery.fraction) <= lowBatteryPercent {
            return .lowBattery
        }
        return nil
    }
}

/// The system-wide setting behind "keep awake with the lid closed": `pmset disablesleep`. It
/// outlives the app and even a restart, so whoever sets it must also see that it is undone.
public enum PowerManagementSetting {
    private static let pmset = URL(fileURLWithPath: "/usr/bin/pmset")

    /// Reads the setting from `pmset -g` output. A setting that is not listed counts as off.
    public static func sleepDisabled(in output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count >= 2, fields[0] == "SleepDisabled" { return fields[1] == "1" }
        }
        return false
    }

    /// The current setting; nil if `pmset` could not be run. Needs no privileges.
    public static func readSleepDisabled() -> Bool? {
        guard let result = run(["-g"]), result.status == 0 else { return nil }
        return sleepDisabled(in: result.output)
    }

    /// A `pmset` that has not finished by then is killed, so a stuck power daemon cannot stall the caller.
    private static let timeoutSeconds = 5.0

    /// Runs `pmset` with fixed arguments and no shell; nil if it could not run or timed out. Its
    /// output is a few lines, far below the pipe's buffer, so it is read after the process ends.
    public static func run(_ arguments: [String]) -> (status: Int32, output: String)? {
        run(pmset, arguments, timeout: timeoutSeconds)
    }

    /// `run` for any executable and time limit, so the limit can be tested.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
