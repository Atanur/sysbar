import Foundation
import SysbarCore

struct SSHRunnerError: Error, Equatable {
    let message: String
}

/// Runs the remote script over the system `ssh`. The blocking work happens off the main thread.
///
/// Connections are shared through a control socket in a private temporary directory, so only the
/// first sample pays for the handshake. `closeConnection` ends that shared connection.
final class SSHRunner: @unchecked Sendable {
    private static let timeoutSeconds = 12.0
    private static let sshPath = "/usr/bin/ssh"

    private let lock = NSLock()
    private var running: Process?
    private let controlPath: String
    private let extraOptions: [String]

    init(extraOptions: [String] = []) {
        self.extraOptions = extraOptions
        // Writing the script to an ssh that already failed would otherwise raise SIGPIPE and kill the app.
        signal(SIGPIPE, SIG_IGN)
        let directory = "/tmp/sysbar-\(getuid())"
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        controlPath = "\(directory)/c-%C"
    }

    func run(_ device: RemoteDevice) async -> Result<String, SSHRunnerError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.runBlocking(device))
            }
        }
    }

    /// Stops a sample that is still in flight.
    func cancel() {
        lock.lock()
        let process = running
        lock.unlock()
        process?.terminate()
    }

    /// Closes the shared connection to `device` now and returns once ssh has done so.
    ///
    /// The popover does not call this when it closes: the connection is left to expire after
    /// `SSHCommand.keepAliveSeconds`, so reopening soon after does not log in again. It is for the
    /// cases where a warm connection must not be reused: before a connection test (it would skip
    /// authentication and hide a wrong key), when a device is edited or deleted, and when the app quits.
    func closeConnectionNow(_ device: RemoteDevice) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.sshPath)
        process.arguments = SSHCommand.exitArguments(for: device, controlPath: controlPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// Same as `closeConnectionNow`, off the calling thread.
    func closeConnection(_ device: RemoteDevice) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.closeConnectionNow(device)
                continuation.resume()
            }
        }
    }

    // MARK: Blocking run

    private final class Capture: @unchecked Sendable {
        var data = Data()
        var timedOut = false
    }

    private func runBlocking(_ device: RemoteDevice) -> Result<String, SSHRunnerError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.sshPath)
        process.arguments = SSHCommand.arguments(for: device, controlPath: controlPath, extraOptions: extraOptions)
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return .failure(SSHRunnerError(message: L("Could not start ssh: %@", error.localizedDescription)))
        }
        lock.lock()
        running = process
        lock.unlock()
        defer {
            lock.lock()
            running = nil
            lock.unlock()
        }

        let standardOutput = Capture()
        let standardError = Capture()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                standardError.timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds, execute: watchdog)

        let readers = DispatchGroup()
        for (pipe, capture) in [(output, standardOutput), (errors, standardError)] {
            readers.enter()
            DispatchQueue.global().async {
                capture.data = pipe.fileHandleForReading.readDataToEndOfFile()
                readers.leave()
            }
        }

        try? input.fileHandleForWriting.write(contentsOf: Data(RemoteScript.source.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        readers.wait()
        watchdog.cancel()

        if standardError.timedOut {
            return .failure(SSHRunnerError(message: L("The connection timed out.")))
        }
        guard process.terminationStatus == 0 else {
            let text = String(decoding: standardError.data, as: UTF8.self)
            let message = SSHFailure.message(stderr: text, exitCode: process.terminationStatus, host: device.host)
            return .failure(SSHRunnerError(message: message))
        }
        return .success(String(decoding: standardOutput.data, as: UTF8.self))
    }
}
