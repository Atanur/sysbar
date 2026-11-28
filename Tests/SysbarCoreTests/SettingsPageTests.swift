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
            .thisMac, .device(first), .findDevices, .general, .menuBarReadouts, .menuBarAppearance, .notch,
            .panel, .fans, .keepAwake, .shelf, .clipboard, .about,
        ]
        #expect(Set(pages) == Set(expected))
    }

    @Test func theSidebarStartsWithHowSysbarShowsItselfAndEndsWithAbout() {
        #expect(SettingsSection.allCases == [.display, .features, .devices, .about])
        #expect(SettingsSection.display.pages(deviceIDs: []) == [.general, .menuBarReadouts, .menuBarAppearance, .notch, .panel])
        #expect(SettingsSection.allCases.last?.pages(deviceIDs: [first]) == [.about])
    }

    @Test func onlyTheFeaturesAndTheDevicesHaveAHeader() {
        #expect(SettingsSection.allCases.filter(\.hasHeader) == [.features, .devices])
    }

    @Test func findingDevicesIsReachedFromTheAddButtonNotTheSidebar() {
        let sidebar = SettingsSection.allCases.flatMap { $0.pages(deviceIDs: [first]) }
        #expect(!sidebar.contains(.findDevices))
    }

    @Test func theClipboardHasItsOwnPageNextToTheStash() {
        let features = SettingsSection.features.pages(deviceIDs: [])
        #expect(features == [.fans, .keepAwake, .shelf, .clipboard])
    }

    @Test func onlyTheMenuBarAndNotchPagesBelongToAPlacement() {
        #expect(SettingsPage.menuBarAppearance.placement == .menuBar)
        #expect(SettingsPage.notch.placement == .notch)
        let others = SettingsPage.all(deviceIDs: [first]).filter { $0 != .menuBarAppearance && $0 != .notch }
        #expect(others.allSatisfy { $0.placement == nil })
    }

    @Test func theWindowOpensOnTheFirstPageOfTheSidebar() {
        #expect(SettingsPage.start == SettingsSection.allCases.first?.pages(deviceIDs: []).first)
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
