import Foundation

/// The short how-to under the device list: what to run on a Mac or a Linux server, and then on this
/// Mac, so Sysbar can log in with a key. Sysbar runs none of it and never asks for a password; the
/// user copies each command into Terminal.
public enum DeviceSetupGuide {
    public enum System: CaseIterable, Sendable {
        case mac, linux
    }

    /// A command to copy, with an optional label when there is one per distribution.
    public struct Command: Equatable, Sendable {
        public let label: String?
        public let text: String
    }

    public struct Step: Equatable, Sendable {
        public let title: String
        public let detail: String
        public let commands: [Command]
        /// True for a step this Mac has already done, such as making a key.
        public let isOptional: Bool
    }

    /// Stands in for what the address step prints.
    public static let destination = "USER@ADDRESS"

    /// The public keys ssh offers by default, newest kind first.
    private static let defaultKeyNames = ["id_ed25519_sk", "id_ed25519", "id_ecdsa_sk", "id_ecdsa", "id_rsa"]

    /// `existingKey` is the key this Mac already has, as from `defaultKey(in:exists:)`.
    ///
    /// For a device Sysbar found, `destination` is its "user@address": the commands use it, and the
    /// step that finds the address is left out. `sshIsOn` marks turning on SSH as already done.
    public static func steps(
        for system: System, existingKey: String?, destination: String? = nil, sshIsOn: Bool = false
    ) -> [Step] {
        guard let destination else {
            return remoteSteps(for: system) + localSteps(existingKey: existingKey, destination: nil)
        }
        let turnOn = remoteSteps(for: system)[0]
        let first = sshIsOn
            ? Step(title: turnOn.title, detail: L("It is already on, so you can skip this step."), commands: turnOn.commands, isOptional: true)
            : turnOn
        return [first] + localSteps(existingKey: existingKey, destination: destination)
    }

    /// The first default key found, shown as `~/.ssh/<name>`, or nil if there is none. Newer kinds
    /// come first, so a Mac with both an ed25519 and an rsa key names the ed25519 one.
    public static func defaultKey(in directory: String, exists: (String) -> Bool) -> String? {
        defaultKeyNames
            .first { exists("\(directory)/\($0).pub") }
            .map { "~/.ssh/\($0)" }
    }

    private static func remoteSteps(for system: System) -> [Step] {
        switch system {
        case .mac:
            [
                Step(
                    title: L("On the Mac to watch: turn on Remote Login"),
                    detail: L("System Settings › General › Sharing › Remote Login. Or run this in its Terminal:"),
                    commands: [Command(label: nil, text: "sudo systemsetup -setremotelogin on")],
                    isOptional: false
                ),
                Step(
                    title: L("On the Mac to watch: find its address and user name"),
                    detail: L("This prints both. The .local name works on the same network; over a VPN such as Tailscale, use the address the VPN shows instead."),
                    commands: [Command(label: nil, text: #"echo "$(whoami)@$(scutil --get LocalHostName).local""#)],
                    isOptional: false
                ),
            ]
        case .linux:
            [
                Step(
                    title: L("On the server: install and start the SSH server"),
                    detail: L("Most servers already run it, and running this again does no harm."),
                    commands: [
                        Command(label: "Debian, Ubuntu", text: "sudo apt install -y openssh-server && sudo systemctl enable --now ssh"),
                        Command(label: "Fedora, RHEL", text: "sudo dnf install -y openssh-server && sudo systemctl enable --now sshd"),
                    ],
                    isOptional: false
                ),
                Step(
                    title: L("On the server: find its address and user name"),
                    detail: L("This prints both. Over a VPN such as Tailscale, use the address the VPN shows instead."),
                    commands: [Command(label: nil, text: #"echo "$(whoami)@$(hostname -I | cut -d' ' -f1)""#)],
                    isOptional: false
                ),
            ]
        }
    }

    private static func localSteps(existingKey: String?, destination known: String?) -> [Step] {
        let destination = known ?? Self.destination
        return [
            Step(
                title: L("On this Mac: make an ssh key"),
                detail: existingKey.map { L("You already have one, %@, so you can skip this step.", $0) }
                    ?? L("Press Return at each question to keep the defaults."),
                commands: [Command(label: nil, text: "ssh-keygen -t ed25519")],
                isOptional: existingKey != nil
            ),
            Step(
                title: L("On this Mac: copy the key over"),
                detail: known == nil
                    ? L("Put what step 2 printed in place of USER@ADDRESS. Type yes to trust the device, then its password, once. The password goes from Terminal to the device; Sysbar never sees it.")
                    : L("Type yes to trust the device, then its password, once. The password goes from Terminal to the device; Sysbar never sees it."),
                commands: [Command(label: nil, text: "ssh-copy-id \(destination)")],
                isOptional: false
            ),
            Step(
                title: L("On this Mac: check it"),
                detail: known == nil
                    ? L("If this returns without asking for anything, click Add device and fill in the same address and user name.")
                    : L("If this returns without asking for anything, click Add device."),
                commands: [Command(label: nil, text: "ssh -o BatchMode=yes \(destination) true")],
                isOptional: false
            ),
        ]
    }
}
