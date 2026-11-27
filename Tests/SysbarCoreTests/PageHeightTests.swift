import CoreGraphics
import Testing
@testable import SysbarCore

@Suite struct PageHeightTests {
    @Test func aTallScreenAllowsTheCap() {
        #expect(PageHeight.limit(visibleHeight: 1000) == PageHeight.cap)
    }

    @Test func aShortScreenLowersTheCapButNeverBelowTheFloor() {
        #expect(PageHeight.limit(visibleHeight: 500) == 500 - PageHeight.screenMargin)
        #expect(PageHeight.limit(visibleHeight: 200) == PageHeight.floor)
    }

    @Test func aListIsAsTallAsItsRowsAndPadding() {
        #expect(PageHeight.list(rows: 3, rowHeight: 38, spacing: 1, padding: 0, room: 300) == CGFloat(3 * 38 + 2))
        #expect(PageHeight.list(rows: 3, rowHeight: 46, spacing: 2, padding: 6, room: 300) == CGFloat(3 * 46 + 4 + 12))
    }

    @Test func aLongListStopsAtTheRoomItIsGiven() {
        #expect(PageHeight.list(rows: 100, rowHeight: 38, spacing: 1, room: 250) == 250)
    }

    @Test func anEmptyListIsAsTallAsItsPadding() {
        #expect(PageHeight.list(rows: 0, rowHeight: 38, spacing: 1, padding: 6, room: 250) == 12)
        #expect(PageHeight.list(rows: -2, rowHeight: 38, room: 250) == 0)
    }

    @Test func noRoomMeansNoList() {
        #expect(PageHeight.list(rows: 5, rowHeight: 38, room: -10) == 0)
    }
}
