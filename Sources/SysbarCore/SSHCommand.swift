import Foundation

/// Builds the `ssh` invocation for a device. Always non-interactive (`BatchMode`), so a missing key
/// or an unknown host fails with a message instead of hanging on a prompt, and connections are
/// shared through a control socket so repeated samples do not renegotiate each time.
public enum SSHCommand {
    private static let connectTimeoutSeconds = 5

    /// How long the shared connection stays open once nothing is using it. Closing the popover does
    /// not close it, so opening it again soon after reuses the connection instead of logging in
    /// again; after this long it closes by itself and nothing is left running on either side.
    public static let keepAliveSeconds = 60

    /// `extraOptions` are extra ssh arguments placed before the destination. The app passes none;
    /// the `--remote-test` diagnostic uses it to point at a throwaway known_hosts file.
    public static func arguments(
        for device: RemoteDevice, controlPath: String, extraOptions: [String] = []
    ) -> [String] {
        var args = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=\(keepAliveSeconds)",
        ]
        if let port = device.port { args += ["-p", String(port)] }
        if !device.identityFile.isEmpty {
            args += ["-i", NSString(string: device.identityFile).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
        }
        if !device.user.isEmpty { args += ["-l", device.user] }
        return args + extraOptions + ["--", device.host, "sh", "-s"]
    }

    /// Asks the shared master connection to close. The control path hash depends on the endpoint,
    /// so the port and user must match the connection being closed.
    public static func exitArguments(for device: RemoteDevice, controlPath: String) -> [String] {
        var args = ["-O", "exit", "-o", "ControlPath=\(controlPath)"]
        if let port = device.port { args += ["-p", String(port)] }
        if !device.user.isEmpty { args += ["-l", device.user] }
        return args + ["--", device.host]
    }
}

/// Turns ssh's raw error output into a short, localized explanation.
public enum SSHFailure {
    public static func message(stderr: String, exitCode: Int32, host: String) -> String {
        let text = stderr.lowercased()
        if text.contains("remote host identification has changed") {
            return L("The server's key has changed. Sysbar did not connect, for your safety; check the server.")
        }
        if text.contains("host key verification failed") {
            return L("The server's key could not be verified. Connect once in Terminal with `ssh %@` and accept it.", host)
        }
        if text.contains("permission denied") {
            return L("Authentication failed. Passwords are not supported; use an ssh key or ssh-agent.")
        }
        if text.contains("could not resolve hostname") { return L("The host name could not be resolved. Check the name.") }
        if text.contains("connection refused") { return L("The connection was refused. Is the SSH server running?") }
        if text.contains("timed out") { return L("The connection timed out.") }
        if text.contains("no route to host") || text.contains("network is unreachable") {
            return L("The server is unreachable.")
        }
        let lastLine = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return lastLine ?? L("Unknown error (code %@).", "\(exitCode)")
    }
}
