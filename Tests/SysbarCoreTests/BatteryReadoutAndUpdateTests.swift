import Foundation
import Testing
@testable import SysbarCore

@Suite struct BatteryMenuBarTests {
    private func battery(_ fraction: Double, plugged: Bool = false) -> BatteryInfo {
        BatteryInfo(
            fraction: fraction, isPluggedIn: plugged, isCharging: false, isFull: false, minutesRemaining: nil,
            cycleCount: nil, health: nil, adapterWatts: nil, batteryWatts: nil
        )
    }

    private func snapshot(battery: BatteryInfo?) -> Snapshot {
        Snapshot(
            timestamp: .distantPast, cpuUsage: 0.2,
            memory: MemoryReading(usedBytes: 4, totalBytes: 10, pressure: .normal),
            power: nil, systemPower: nil, battery: battery
        )
    }

    @Test func showsOnlyOnBatteryAtOrBelowTheThreshold() {
        #expect(BatteryMenuBar.isShown(battery(0.5), threshold: 50))
        #expect(!BatteryMenuBar.isShown(battery(0.51), threshold: 50))
        #expect(BatteryMenuBar.isShown(battery(1), threshold: 100))
        #expect(!BatteryMenuBar.isShown(battery(0.1, plugged: true), threshold: 100))
        #expect(!BatteryMenuBar.isShown(battery(0.1), threshold: BatteryMenuBar.off))
        #expect(!BatteryMenuBar.isShown(nil, threshold: 100))
    }

    @Test func unknownStoredThresholdsFallBackToTheDefault() {
        #expect(BatteryMenuBar.normalized(nil) == BatteryMenuBar.defaultThreshold)
        #expect(BatteryMenuBar.normalized(37) == BatteryMenuBar.defaultThreshold)
        #expect(BatteryMenuBar.normalized(0) == 0)
        #expect(BatteryMenuBar.normalized(20) == 20)
    }

    @Test func chargeColoursRunFromGreenToRed() {
        #expect(LoadLevel.battery(charge: 0.8) == .low)
        #expect(LoadLevel.battery(charge: 0.51) == .low)
        #expect(LoadLevel.battery(charge: 0.5) == .moderate)
        #expect(LoadLevel.battery(charge: 0.3) == .high)
        #expect(LoadLevel.battery(charge: 0.2) == .critical)
        #expect(LoadLevel.battery(charge: -1) == .critical)
    }

    @Test func batteryReadoutComesLastAndKeepsItsColour() {
        let readouts = MenuBarReadouts.make(from: snapshot(battery: battery(0.42)), metrics: [.cpu], batteryThreshold: 50)

        #expect(readouts.map(\.slot) == [.metric(.cpu), .battery])
        let battery = readouts[1]
        #expect(battery.text == "42%")
        #expect(battery.load == .moderate)
        #expect(battery.isAlwaysColored)
        #expect(battery.metric == nil)
        #expect(!readouts[0].isAlwaysColored)
    }

    @Test func noBatteryReadoutAboveTheThresholdOrWhenOff() {
        let full = snapshot(battery: battery(0.9))
        #expect(MenuBarReadouts.make(from: full, metrics: [.cpu], batteryThreshold: 50).map(\.slot) == [.metric(.cpu)])
        #expect(MenuBarReadouts.make(from: full, metrics: [.cpu]).count == 1)
    }

    @Test func tooltipMentionsTheBatteryWhenShown() {
        let low = snapshot(battery: battery(0.15))
        #expect(Format.statusTitle(low, metrics: [.cpu], batteryThreshold: 20) == "CPU 20% · Battery 15%")
    }
}

@Suite struct UpdateCheckTests {
    private func reply(
        tag: String = "v0.2.0", page: String = "https://github.com/Atanur/sysbar/releases/tag/v0.2.0",
        asset: String = "Sysbar-0.2.0.zip",
        download: String = "https://github.com/Atanur/sysbar/releases/download/v0.2.0/Sysbar-0.2.0.zip",
        draft: Bool = false, prerelease: Bool = false, body: String = "- Faster\\r\\n- Smaller"
    ) -> Data {
        let json = """
        {"tag_name":"\(tag)","html_url":"\(page)","draft":\(draft),"prerelease":\(prerelease),"body":"\(body)",
         "assets":[{"name":"\(asset)","browser_download_url":"\(download)"}]}
        """
        return Data(json.utf8)
    }

    @Test func versionsCompareNumerically() throws {
        let older = try #require(AppVersion("v0.9.9"))
        let newer = try #require(AppVersion("0.10.0"))
        #expect(older < newer)
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(AppVersion("1.2.3")?.description == "1.2.3")
    }

    @Test func rejectsTagsThatAreNotVersions() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.0-beta") == nil)
        #expect(AppVersion("1..0") == nil)
        #expect(AppVersion("1.0.0.0.0") == nil)
        #expect(AppVersion("١.٢") == nil)
    }

    @Test func readsTheLatestRelease() throws {
        let release = try #require(UpdateCheck.parseRelease(reply()))
        #expect(release.version == AppVersion("0.2.0"))
        #expect(release.pageURL.absoluteString.hasSuffix("/tag/v0.2.0"))
        #expect(release.downloadURL?.lastPathComponent == "Sysbar-0.2.0.zip")
        #expect(release.notes == ["Faster", "Smaller"])
    }

    @Test func ignoresDraftsPrereleasesAndForeignLinks() {
        #expect(UpdateCheck.parseRelease(reply(draft: true)) == nil)
        #expect(UpdateCheck.parseRelease(reply(prerelease: true)) == nil)
        #expect(UpdateCheck.parseRelease(reply(page: "https://example.com/atanur/sysbar/x")) == nil)
        #expect(UpdateCheck.parseRelease(reply(page: "http://github.com/atanur/sysbar/x")) == nil)
        #expect(UpdateCheck.parseRelease(Data("not json".utf8)) == nil)
    }

    @Test func rejectsLinksThatCouldLeaveTheRepository() {
        let bad = [
            "https://github.com/atanur/sysbar/../../evil/x/releases/download/v1/Sysbar-1.zip",
            "https://github.com/atanur/sysbar/%2e%2e/evil/releases/download/v1/Sysbar-1.zip",
            "https://github.com:8443/atanur/sysbar/releases/download/v1/Sysbar-1.zip",
            "https://someone@github.com/atanur/sysbar/releases/download/v1/Sysbar-1.zip",
        ]
        for link in bad {
            #expect(!UpdateCheck.isRepositoryLink(URL(string: link)!), "\(link)")
        }
        #expect(UpdateCheck.isRepositoryLink(URL(string: "https://github.com/Atanur/sysbar/releases/tag/v1")!))
    }

    @Test func onlyTheMatchingArchiveFromThisRepositoryIsDownloaded() {
        let foreign = UpdateCheck.parseRelease(reply(download: "https://github.com/someone/else/releases/download/v0.2.0/Sysbar-0.2.0.zip"))
        #expect(foreign != nil)
        #expect(foreign?.downloadURL == nil)
        #expect(UpdateCheck.parseRelease(reply(asset: "Other.zip"))?.downloadURL == nil)
    }

    @Test func offersOnlyNewerReleasesThatWereNotSkipped() throws {
        let release = try #require(UpdateCheck.parseRelease(reply()))
        #expect(UpdateCheck.offer(release, current: AppVersion("0.1.0"), skipped: nil) == release)
        #expect(UpdateCheck.offer(release, current: AppVersion("0.2.0"), skipped: nil) == nil)
        #expect(UpdateCheck.offer(release, current: AppVersion("0.3.0"), skipped: nil) == nil)
        #expect(UpdateCheck.offer(release, current: AppVersion("0.1.0"), skipped: AppVersion("0.2.0")) == nil)
        #expect(UpdateCheck.offer(release, current: AppVersion("0.1.0"), skipped: AppVersion("0.1.5")) == release)
        #expect(UpdateCheck.offer(release, current: nil, skipped: nil) == nil)
    }

    @Test func checksAtMostOnceADay() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-UpdateCheck.checkInterval), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(86_400 * 3), now: now))
    }
}
