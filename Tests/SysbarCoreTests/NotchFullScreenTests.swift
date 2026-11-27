import CoreGraphics
import Testing
@testable import SysbarCore

@Suite struct NotchFullScreenTests {
    private let own: Int32 = 100
    private let builtIn = FullScreenDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1800, height: 1169), inFullScreenSpace: false)
    private let external = FullScreenDisplay(id: 2, bounds: CGRect(x: 1800, y: 0, width: 2560, height: 1440), inFullScreenSpace: false)

    private func window(_ bounds: CGRect, pid: Int32 = 7, layer: Int = 0, alpha: Double = 1) -> FullScreenWindow {
        FullScreenWindow(pid: pid, layer: layer, bounds: bounds, alpha: alpha)
    }

    private func detect(_ windows: [FullScreenWindow], _ screens: [FullScreenDisplay]) -> Set<UInt32> {
        FullScreenDetection.displays(windows: windows, screens: screens, ownPID: own)
    }

    @Test func aWindowCoveringTheWholeDisplayIsFullScreen() {
        #expect(detect([window(builtIn.bounds)], [builtIn]) == [1])
    }

    @Test func aMaximisedWindowBelowTheMenuBarIsNotFullScreen() {
        let zoomed = CGRect(x: 0, y: 39, width: 1800, height: 1130)
        #expect(detect([window(zoomed)], [builtIn]).isEmpty)
    }

    @Test func aFullScreenSpaceCountsWhateverTheWindowsLookLike() {
        // On a notched display the app's window starts below the notch, like a maximised one does.
        let below = CGRect(x: 0, y: 39, width: 1800, height: 1130)
        let inSpace = FullScreenDisplay(id: 1, bounds: builtIn.bounds, inFullScreenSpace: true)
        #expect(detect([window(below)], [inSpace]) == [1])
        #expect(detect([], [inSpace]) == [1])
    }

    @Test func eachDisplayIsJudgedOnItsOwn() {
        #expect(detect([window(external.bounds)], [builtIn, external]) == [2])
        let inSpace = FullScreenDisplay(id: 1, bounds: builtIn.bounds, inFullScreenSpace: true)
        #expect(detect([window(external.bounds)], [inSpace, external]) == [1, 2])
    }

    @Test func aWindowOfSysbarItselfNeverCounts() {
        #expect(detect([window(builtIn.bounds, pid: own)], [builtIn]).isEmpty)
    }

    @Test func onlyNormalLevelVisibleWindowsCount() {
        // The wallpaper and desktop sit below layer 0, menus and screenshot overlays above it.
        #expect(detect([window(builtIn.bounds, layer: -2_147_483_624)], [builtIn]).isEmpty)
        #expect(detect([window(builtIn.bounds, layer: 24)], [builtIn]).isEmpty)
        #expect(detect([window(builtIn.bounds, alpha: 0)], [builtIn]).isEmpty)
    }

    @Test func aSmallerWindowIsNotFullScreen() {
        #expect(detect([window(CGRect(x: 100, y: 100, width: 800, height: 600))], [builtIn]).isEmpty)
    }

    @Test func aPointOfSlackAtTheEdgesIsForgiven() {
        let nearly = CGRect(x: 0.5, y: 0.5, width: 1799, height: 1168)
        #expect(detect([window(nearly)], [builtIn]) == [1])
    }
}

@Suite struct NotchIslandVisibilityTests {
    @Test func alwaysShowsTheIslandExceptInFullScreen() {
        #expect(!NotchIslandVisibility.always.isConcealed(fullScreen: false))
        #expect(NotchIslandVisibility.always.isConcealed(fullScreen: true))
    }

    @Test func pointerOnlyConcealsItEverywhere() {
        #expect(NotchIslandVisibility.pointer.isConcealed(fullScreen: false))
        #expect(NotchIslandVisibility.pointer.isConcealed(fullScreen: true))
    }

    @Test func theRevealZoneIsTheStripWithSlackReachingTheScreensTop() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let strip = CGRect(x: 756, y: 1131, width: 308, height: 38)
        let zone = IslandRevealZone.rect(strip: strip, screenTop: screen.maxY)
        #expect(zone.contains(CGPoint(x: 900, y: 1150)))
        // The very top edge, where the pointer stops when pushed up.
        #expect(zone.contains(CGPoint(x: 900, y: 1169)))
        #expect(zone.contains(CGPoint(x: 750, y: 1140)))
        #expect(!zone.contains(CGPoint(x: 700, y: 1150)))
        #expect(!zone.contains(CGPoint(x: 900, y: 1100)))
    }

    @Test func theRevealZoneKeepsItsWidthOnADisplayWithoutANotch() {
        let strip = CGRect(x: 800, y: 1156, width: 200, height: 24)
        let zone = IslandRevealZone.rect(strip: strip, screenTop: 1180)
        #expect(zone.contains(CGPoint(x: 900, y: 1180)))
        #expect(!zone.contains(CGPoint(x: 1100, y: 1170)))
    }
}
