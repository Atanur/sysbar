import Foundation
import Testing
@testable import SysbarCore

@Suite struct DeviceDiscoveryTests {
    private let thisMac = DeviceDiscovery.LocalService(name: "Studio", host: "Studio.local.")

    private func peer(_ name: String, _ machine: String, _ address: String, online: Bool = true, system: DeviceSetupGuide.System = .mac) -> DeviceDiscovery.TailscalePeer {
        DeviceDiscovery.TailscalePeer(name: name, dnsName: "\(machine).tail1.ts.net", system: system, address: address, isOnline: online)
    }

    @Test func readsMacsAndLinuxMachinesFromTailscaleStatus() {
        let json = """
        {"Self": {"HostName": "Studio", "OS": "macOS", "TailscaleIPs": ["100.64.0.1"], "Online": true},
         "Peer": {
          "a": {"HostName": "server", "DNSName": "server.tail1.ts.net.", "OS": "linux", "TailscaleIPs": ["fd7a::2", "100.64.0.2"], "Online": true},
          "b": {"HostName": "Air", "DNSName": "air.tail1.ts.net.", "OS": "macOS", "TailscaleIPs": ["100.64.0.3"], "Online": false},
          "c": {"HostName": "localhost", "DNSName": "phone.tail1.ts.net.", "OS": "iOS", "TailscaleIPs": ["100.64.0.4"], "Online": true}
         }}
        """
        let peers = DeviceDiscovery.tailscalePeers(fromStatusJSON: Data(json.utf8)).sorted { $0.address < $1.address }

        #expect(peers.map(\.address) == ["100.64.0.2", "100.64.0.3"])
        #expect(peers.map(\.system) == [.linux, .mac])
        #expect(peers.first?.dnsName == "server.tail1.ts.net")
        #expect(peers.first?.machineName == "server")
        #expect(peers.last?.isOnline == false)
    }

    @Test func unreadableOrStoppedTailscaleGivesNoPeers() {
        #expect(DeviceDiscovery.tailscalePeers(fromStatusJSON: Data("not json".utf8)).isEmpty)
        #expect(DeviceDiscovery.tailscalePeers(fromStatusJSON: Data(#"{"BackendState": "Stopped", "Peer": null}"#.utf8)).isEmpty)
    }

    @Test func aMacSeenOnBothIsOneDeviceWithBothAddresses() {
        let found = DeviceDiscovery.merge(
            local: [.init(name: "Air", host: "Air.local."), .init(name: "Air", host: "Air.local.")],
            tailscale: [peer("Air", "air", "100.64.0.3")], thisMac: thisMac, added: []
        )

        #expect(found.count == 1)
        #expect(found.first?.localHost == "Air.local")
        #expect(found.first?.hosts == ["100.64.0.3", "Air.local"])
        #expect(found.first?.system == .mac)
    }

    @Test func thisMacAndAddedDevicesAreLeftOut() {
        let found = DeviceDiscovery.merge(
            local: [.init(name: "studio", host: "Other.local"), .init(name: "Mini", host: "Mini.local")],
            tailscale: [peer("server", "vps", "100.64.0.2", system: .linux), peer("Pi", "pi", "100.64.0.5", system: .linux)],
            thisMac: thisMac, added: ["vps", "mini.local."]
        )

        #expect(found.map(\.name) == ["Pi"])
    }

    @Test func reachableDevicesComeFirst() {
        let found = DeviceDiscovery.merge(
            local: [.init(name: "Mini", host: "Mini.local")],
            tailscale: [peer("Air", "air", "100.64.0.3", online: false), peer("Box", "box", "100.64.0.6")],
            thisMac: thisMac, added: []
        )

        #expect(found.map(\.name) == ["Box", "Mini", "Air"])
        #expect(found.last?.isReachable == false)
    }
}
