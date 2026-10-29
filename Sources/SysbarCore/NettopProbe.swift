import Foundation

/// Reads per-process network counters from macOS's `nettop`.
///
/// `nettop` reports cumulative bytes per process, which the sampler turns into rates. It counts
/// TCP and UDP sockets on the interfaces the sockets use; loopback is left out so copying a file
/// on the same Mac does not look like internet use. Stateful: use from one queue only.
public final class NettopProbe {
    private static let executable = "/usr/bin/nettop"
    /// `nettop -L 1` normally answers in a few milliseconds. A stuck one is killed rather than
    /// holding up the apps table.
    private static let timeoutSeconds = 2.0
    /// When `nettop` cannot run, wait this long before trying again instead of starting it on every
    /// sample. A Mac where reading fails then costs nothing between attempts.
    private static let retrySeconds: TimeInterval = 60

    private var retryAfter: Date?

    public init() {}

    /// Cumulative bytes by process id, or nil when the reading is unavailable. A process with no
    /// network activity is absent, which the caller treats as zero.
    public func sample(now: Date = Date()) -> [Int32: ByteCounters]? {
        if let retryAfter, now < retryAfter { return nil }
        guard let output = Self.run() else {
            retryAfter = now.addingTimeInterval(Self.retrySeconds)
            return nil
        }
        retryAfter = nil
        return NettopParser.parse(output)
    }

    private static func run() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-P", "-L", "1", "-x", "-n", "-t", "external"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let capture = Capture()
        let readerDone = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        DispatchQueue.global(qos: .utility).async {
            capture.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readerDone.signal()
        }

        guard finished.wait(timeout: .now() + timeoutSeconds) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            _ = readerDone.wait(timeout: .now() + 1)
            return nil
        }
        process.waitUntilExit()
        readerDone.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: capture.data, as: UTF8.self)
    }

    private final class Capture {
        var data = Data()
    }
}

/// Reads the CSV `nettop -P -L 1 -x` prints. Its process column is `name.pid`; a name may itself
/// contain dots or commas, so the pid is the last dot-separated part of whichever field carries it,
/// and the byte counters are the two fields after the empty interface and state columns.
public enum NettopParser {
    public static func parse(_ output: String) -> [Int32: ByteCounters] {
        var counters: [Int32: ByteCounters] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            for processIndex in 1..<fields.count {
                guard
                    let pid = pid(of: fields[processIndex]),
                    processIndex + 4 < fields.count,
                    fields[processIndex + 1].isEmpty,
                    fields[processIndex + 2].isEmpty,
                    let received = UInt64(fields[processIndex + 3].trimmingCharacters(in: .whitespaces)),
                    let sent = UInt64(fields[processIndex + 4].trimmingCharacters(in: .whitespaces))
                else { continue }
                let previous = counters[pid] ?? ByteCounters(received: 0, sent: 0)
                counters[pid] = ByteCounters(
                    received: previous.received + received, sent: previous.sent + sent
                )
                break
            }
        }
        return counters
    }

    private static func pid(of field: Substring) -> Int32? {
        guard let dot = field.lastIndex(of: ".") else { return nil }
        let suffix = field[field.index(after: dot)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }), let pid = Int32(suffix), pid > 0 else {
            return nil
        }
        return pid
    }
}
