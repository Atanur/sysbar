import Foundation
import Testing
@testable import SysbarCore

@Suite struct SettingsPageTests {
    private let first = UUID()
    private let second = UUID()

    @Test func devicesSectionListsThisMacFirstThenEachDeviceInOrder() {
        #expect(SettingsSection.devices.pages(deviceIDs: [first, second]) == [.thisMac, .device(first), .device(second)])
    }

    @Test func devicesSectionAlwaysHasThisMac() {
        #expect(SettingsSection.devices.pages(deviceIDs: []) == [.thisMac])
    }

    @Test func aRemovedDevicesPageFallsBackToThisMac() {
        #expect(SettingsPage.device(first).resolved(deviceIDs: [second]) == .thisMac)
    }

    @Test func pagesThatStillExistAreKept() {
        #expect(SettingsPage.device(first).resolved(deviceIDs: [first]) == .device(first))
        #expect(SettingsPage.about.resolved(deviceIDs: []) == .about)
        #expect(SettingsPage.findDevices.resolved(deviceIDs: []) == .findDevices)
    }

    @Test func everyPageIsReachableExactlyOnce() {
        let pages = SettingsPage.all(deviceIDs: [first])
        #expect(Set(pages).count == pages.count)
        let expected: [SettingsPage] = [
            .thisMac, .device(first), .findDevices, .menuBarReadouts, .menuBarAppearance,
            .windowLayout, .appsTable, .fans, .keepAwake, .general, .about,
        ]
        #expect(Set(pages) == Set(expected))
    }

    @Test func findingDevicesIsReachedFromTheAddButtonNotTheSidebar() {
        let sidebar = SettingsSection.allCases.flatMap { $0.pages(deviceIDs: [first]) }
        #expect(!sidebar.contains(.findDevices))
    }

    @Test func theWindowOpensOnThisMac() {
        #expect(SettingsPage.start == .thisMac)
    }
}

@Suite struct DeviceConnectionChangeTests {
    private let device = RemoteDevice(name: "nas", host: "nas.local", user: "me", port: nil, identityFile: "")

    @Test func aNewNameKeepsTheConnection() {
        let renamed = RemoteDevice(id: device.id, name: "Storage", host: "nas.local", user: "me", port: nil, identityFile: "")
        #expect(!renamed.connectsDifferently(from: device))
    }

    @Test func cardsAndSamplingKeepTheConnection() {
        let tuned = RemoteDevice(
            id: device.id, name: "nas", host: "nas.local", user: "me", port: nil, identityFile: "",
            cards: [.cpu], interval: 10, keepMonitoring: .always
        )
        #expect(!tuned.connectsDifferently(from: device))
    }

    @Test(arguments: [
        RemoteDevice(name: "nas", host: "10.0.0.2", user: "me", port: nil, identityFile: ""),
        RemoteDevice(name: "nas", host: "nas.local", user: "root", port: nil, identityFile: ""),
        RemoteDevice(name: "nas", host: "nas.local", user: "me", port: 2222, identityFile: ""),
        RemoteDevice(name: "nas", host: "nas.local", user: "me", port: nil, identityFile: "~/.ssh/nas"),
    ])
    func anotherAddressUserPortOrKeyConnectsAnew(_ changed: RemoteDevice) {
        #expect(changed.connectsDifferently(from: device))
    }
}
