import Foundation
import Testing

@testable import SysbarCore

@Suite("Mirrored scale")
struct MirroredScaleTests {
    @Test("both series share the scale of the higher one")
    func sharedPeak() {
        let result = MirroredScale.fractions(upper: [10, 5], lower: [2, 1])
        let scale = 10 * MirroredScale.headroom
        #expect(abs(result.upper[0] - 10 / scale) < 1e-9)
        #expect(abs(result.upper[1] - 5 / scale) < 1e-9)
        #expect(abs(result.lower[0] - 2 / scale) < 1e-9)
    }

    @Test("equal values come out at equal heights on both sides")
    func equalValuesEqualHeights() {
        let result = MirroredScale.fractions(upper: [4], lower: [4])
        #expect(result.upper == result.lower)
    }

    @Test("the higher series may be the lower one")
    func lowerCanBeThePeak() {
        let result = MirroredScale.fractions(upper: [1], lower: [8])
        #expect(result.lower[0] > result.upper[0])
        #expect(result.lower[0] < 1)
    }

    @Test("nothing to show gives zeros of the same length")
    func allZero() {
        let result = MirroredScale.fractions(upper: [0, 0, 0], lower: [0])
        #expect(result.upper == [0, 0, 0])
        #expect(result.lower == [0])
    }

    @Test("no samples gives no values")
    func empty() {
        let result = MirroredScale.fractions(upper: [], lower: [])
        #expect(result.upper.isEmpty)
        #expect(result.lower.isEmpty)
    }
}

@Suite("Disk space")
struct DiskSpaceTests {
    private func space(freePercent: Double) -> DiskSpace {
        DiskSpace(availableBytes: UInt64(freePercent * 10), totalBytes: 1_000)
    }

    @Test("plenty of room is not flagged")
    func plenty() {
        #expect(space(freePercent: 40).level == .plenty)
        #expect(space(freePercent: 15).level == .plenty)
    }

    @Test("under 15 percent is low, under 5 percent is critical")
    func thresholds() {
        #expect(space(freePercent: 14.9).level == .low)
        #expect(space(freePercent: 5).level == .low)
        #expect(space(freePercent: 4.9).level == .critical)
        #expect(space(freePercent: 0).level == .critical)
    }

    @Test("the share is of the whole volume, and never above one")
    func fraction() {
        #expect(space(freePercent: 25).freeFraction == 0.25)
        #expect(DiskSpace(availableBytes: 2_000, totalBytes: 1_000).freeFraction == 1)
        #expect(DiskSpace(availableBytes: 5, totalBytes: 0).freeFraction == 0)
    }

    @Test("this Mac's startup volume can be read")
    func readsTheStartupVolume() {
        let space = DiskSpaceProbe.read()
        #expect(space != nil)
        #expect((space?.totalBytes ?? 0) > (space?.availableBytes ?? 0))
    }
}

@Suite("Network link")
struct NetworkLinkTests {
    @Test("an interface that does not exist is neither Wi-Fi nor Ethernet")
    func unknownInterface() {
        #expect(NetworkLinkProbe.link(forInterface: "nonexistent0") == .other)
    }
}
