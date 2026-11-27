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

    @Test func thePopoverFollowsItsPageWithinTheRoomBelowTheMenuBar() {
        #expect(PageHeight.popoverHeight(wanted: 580, room: 900) == 580)
        #expect(PageHeight.popoverHeight(wanted: 580, room: 450) == 450)
        #expect(PageHeight.popoverHeight(wanted: 580, room: 50) == PageHeight.floor)
        #expect(PageHeight.popoverHeight(wanted: 100, room: 900) == PageHeight.floor)
    }

    @Test func aListIsAsTallAsItsRowsAndPadding() {
        #expect(PageHeight.list(rows: 3, rowHeight: 38, spacing: 1, padding: 0, room: 300) == CGFloat(3 * 38 + 2))
        #expect(PageHeight.list(rows: 3, rowHeight: 46, spacing: 2, padding: 6, room: 300) == CGFloat(3 * 46 + 4 + 12))
    }

    @Test func aLongListStopsOnAWholeRowWithinTheRoom() {
        // 6 rows of 38 and 5 gaps of 1 are 233; a 7th would need 272.
        #expect(PageHeight.list(rows: 100, rowHeight: 38, spacing: 1, room: 250) == 233)
        #expect(PageHeight.list(rows: 100, rowHeight: 43, spacing: 2, padding: 6, room: 300) == CGFloat(6 + 6 * 43 + 5 * 2))
    }

    @Test func aListThatJustFitsIsNotShortened() {
        #expect(PageHeight.list(rows: 6, rowHeight: 38, spacing: 1, room: 233) == 233)
        #expect(PageHeight.list(rows: 7, rowHeight: 38, spacing: 1, room: 233) == 233)
    }

    @Test func roomForLessThanOneRowIsAllTheListGets() {
        #expect(PageHeight.list(rows: 5, rowHeight: 38, spacing: 1, room: 30) == 30)
    }

    @Test func anEmptyListIsAsTallAsItsPadding() {
        #expect(PageHeight.list(rows: 0, rowHeight: 38, spacing: 1, padding: 6, room: 250) == 12)
        #expect(PageHeight.list(rows: -2, rowHeight: 38, room: 250) == 0)
    }

    @Test func noRoomMeansNoList() {
        #expect(PageHeight.list(rows: 5, rowHeight: 38, room: -10) == 0)
    }
}
