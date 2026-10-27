import Testing
@testable import SysbarCore

@Suite struct DeviceSetupGuideTests {
    private func commands(_ steps: [DeviceSetupGuide.Step]) -> [String] {
        steps.flatMap { $0.commands.map(\.text) }
    }

    @Test func aMacTurnsOnRemoteLoginAndALinuxServerInstallsOpenSSH() {
        let mac = commands(DeviceSetupGuide.steps(for: .mac, existingKey: nil))
        let linux = commands(DeviceSetupGuide.steps(for: .linux, existingKey: nil))

        #expect(mac.contains("sudo systemsetup -setremotelogin on"))
        #expect(!mac.contains { $0.contains("apt") })
        #expect(linux.contains { $0.contains("apt install -y openssh-server") })
        #expect(linux.contains { $0.contains("dnf install -y openssh-server") })
        #expect(!linux.contains { $0.contains("systemsetup") })
    }

    @Test func bothEndWithCopyingTheKeyAndAPasswordlessCheck() {
        for system in DeviceSetupGuide.System.allCases {
            let all = commands(DeviceSetupGuide.steps(for: system, existingKey: nil))
            #expect(all.contains("ssh-keygen -t ed25519"))
            #expect(all.contains("ssh-copy-id USER@ADDRESS"))
            #expect(all.last == "ssh -o BatchMode=yes USER@ADDRESS true")
        }
    }

    @Test func aMacWithAKeyIsToldItCanSkipMakingOne() {
        let without = DeviceSetupGuide.steps(for: .mac, existingKey: nil)
        let with = DeviceSetupGuide.steps(for: .mac, existingKey: "~/.ssh/id_ed25519")
        let keyStep = { (steps: [DeviceSetupGuide.Step]) in
            steps.first { $0.commands.contains { $0.text.hasPrefix("ssh-keygen") } }
        }

        #expect(keyStep(without)?.isOptional == false)
        #expect(keyStep(with)?.isOptional == true)
        #expect(keyStep(with)?.detail.contains("~/.ssh/id_ed25519") == true)
        #expect(with.count == without.count)
    }

    @Test func findsTheFirstDefaultKeyThatSSHWouldOffer() {
        let present: Set<String> = ["/home/.ssh/id_rsa.pub", "/home/.ssh/id_ed25519.pub"]

        #expect(DeviceSetupGuide.defaultKey(in: "/home/.ssh", exists: present.contains) == "~/.ssh/id_ed25519")
        #expect(DeviceSetupGuide.defaultKey(in: "/home/.ssh", exists: { _ in false }) == nil)
    }
}
