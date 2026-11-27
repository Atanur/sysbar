import CoreGraphics
import Foundation
import Testing
@testable import SysbarCore

@Suite struct NotchEarLayoutTests {
    private let everything = Set(NotchItem.allCases)

    @Test func theStandardLayoutHasTheReadoutsLeftAndTheTwoIconsRight() {
        let layout = NotchEarLayout.standard
        #expect(layout.left == [.system])
        #expect(layout.right == [.stash, .clipboard])
        #expect(layout.whenOpen.isEmpty)
        #expect(layout.ears(available: everything, open: false) == (left: [.system], right: [.stash, .clipboard]))
    }

    @Test func duplicatesAreDroppedAndTheFirstPlaceWins() {
        let layout = NotchEarLayout(left: [.stash, .stash, .clipboard], right: [.clipboard, .stash])
        #expect(layout.left == [.stash, .clipboard, .system])
        #expect(layout.right.isEmpty)
        #expect(Set(layout.left + layout.right) == everything)
        #expect((layout.left + layout.right).count == everything.count)
    }

    @Test func anEmptyLayoutBecomesTheStandardOne() {
        #expect(NotchEarLayout(left: [], right: []) == .standard)
    }

    @Test func aMissingItemIsAppendedToItsDefaultEar() {
        let layout = NotchEarLayout(left: [.stash], right: [])
        #expect(layout.left == [.stash, .system])
        #expect(layout.right == [.clipboard])
    }

    @Test func movingAnItemAcrossKeepsEveryItemOnce() {
        let moved = NotchEarLayout.standard.moving(.stash, to: .left, at: 0)
        #expect(moved.left == [.stash, .system])
        #expect(moved.right == [.clipboard])
        let end = moved.moving(.stash, to: .right)
        #expect(end.right == [.clipboard, .stash])
    }

    @Test func anEarMayBeLeftEmpty() {
        let moved = NotchEarLayout.standard.moving(.system, to: .right, at: 0)
        #expect(moved.left.isEmpty)
        #expect(moved.right.first == .system)
    }

    @Test func shiftingStaysInsideTheEar() {
        let layout = NotchEarLayout.standard
        #expect(layout.shifting(.clipboard, by: -1).right == [.clipboard, .stash])
        #expect(layout.shifting(.stash, by: -1) == layout)
        #expect(layout.shifting(.clipboard, by: 1) == layout)
        #expect(layout.shifting(.stash, by: 1).right == [.clipboard, .stash])
    }

    @Test func droppingOneRowOnAnotherPutsItBeforeIt() {
        let layout = NotchEarLayout.standard
        #expect(layout.moving(.clipboard, before: .stash).right == [.clipboard, .stash])
        #expect(layout.moving(.system, before: .clipboard).right == [.stash, .system, .clipboard])
        #expect(layout.moving(.stash, before: .stash) == layout)
    }

    @Test func anItemShownOnlyWhenOpenLeavesTheClosedIsland() {
        let layout = NotchEarLayout.standard.setting(.clipboard, to: .whenOpen)
        #expect(layout.visibility(of: .clipboard) == .whenOpen)
        #expect(layout.ears(available: everything, open: false).right == [.stash])
        #expect(layout.ears(available: everything, open: true).right == [.stash, .clipboard])
        #expect(layout.setting(.clipboard, to: .always) == .standard)
    }

    @Test func unavailableItemsAreLeftOutOfBothStates() {
        let available: Set<NotchItem> = [.system, .stash]
        let layout = NotchEarLayout.standard
        #expect(layout.ears(available: available, open: true) == (left: [.system], right: [.stash]))
        #expect(layout.ears(available: available, open: false) == (left: [.system], right: [.stash]))
    }

    @Test func iconsHiddenBeforeBecomeShownOnlyWhenOpen() {
        let layout = NotchEarLayout.migrated(hiddenFeatures: ["fan", "clipboard", "nonsense", "system"])
        #expect(layout.whenOpen == [.clipboard, .system])
        #expect(layout.left == [.system] && layout.right == NotchEarLayout.standard.right)
        #expect(NotchEarLayout.migrated(hiddenFeatures: []) == .standard)
    }

    @Test func itSurvivesBeingStoredAndSkipsItemsItDoesNotKnow() throws {
        let layout = NotchEarLayout.standard.moving(.stash, to: .left).setting(.clipboard, to: .whenOpen)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(NotchEarLayout.self, from: data) == layout)
        let newer = Data(#"{"left":["hologram","stash"],"right":["clipboard"],"whenOpen":["hologram","clipboard"]}"#.utf8)
        let read = try JSONDecoder().decode(NotchEarLayout.self, from: newer)
        #expect(read.left == [.stash, .system])
        #expect(read.right == [.clipboard])
        #expect(read.whenOpen == [.clipboard])
    }

    @Test func aLayoutStoredWithTheOldFansAndKeepAwakeItemsLosesThem() throws {
        let stored = Data(#"{"left":["system","fan"],"right":["keepAwake","clipboard","stash"],"whenOpen":["fan","keepAwake","stash"]}"#.utf8)
        let read = try JSONDecoder().decode(NotchEarLayout.self, from: stored)
        #expect(read.left == [.system])
        #expect(read.right == [.clipboard, .stash])
        #expect(read.whenOpen == [.stash])
    }

    @Test func garbageDecodesToTheStandardLayout() throws {
        let read = try JSONDecoder().decode(NotchEarLayout.self, from: Data("{}".utf8))
        #expect(read == .standard)
    }
}

@Suite struct NotchEarFitTests {
    private let side = NotchGeometry.featureIconSide
    private func icon(_ item: NotchItem) -> NotchEarEntry { NotchEarEntry(item: item, width: side) }
    private func bars(_ width: CGFloat) -> NotchEarEntry { NotchEarEntry(item: .system, width: width, isBars: true) }

    @Test func iconsSitIconGapApartAndBarsKeepMoreRoom() {
        let entries = [icon(.stash), icon(.clipboard), bars(40), icon(.clipboard)]
        let gap = NotchGeometry.featureIconGap
        let barsGap = NotchGeometry.barsGap
        #expect(NotchGeometry.earOffsets(entries) == [0, side + gap, 2 * side + gap + barsGap, 2 * side + gap + 40 + 2 * barsGap])
        #expect(NotchGeometry.earWidth(entries) == 3 * side + gap + 40 + 2 * barsGap)
        #expect(NotchGeometry.earWidth([]) == 0)
    }

    @Test func theStandardRightEarStillFits() {
        let entries = [.stash, .clipboard].map(icon)
        #expect(NotchGeometry.fit(entries, ear: .right) == entries)
        #expect(NotchGeometry.earWidth(entries) == NotchGeometry.featureIconsWidth(2))
    }

    @Test func statusGlyphsComeBeforeTheItemsAndTheirWidthCounts() {
        let items = [.stash, .clipboard].map(icon)
        let entries = NotchGeometry.withStatuses([.heat, .keepAwake], side: side, before: items)
        #expect(entries.map(\.slot) == [.status(.heat), .status(.keepAwake), .item(.stash), .item(.clipboard)])
        #expect(entries.map(\.item) == [nil, nil, .stash, .clipboard])
        #expect(NotchGeometry.earWidth(entries) == NotchGeometry.featureIconsWidth(4))
        #expect(NotchGeometry.fit(entries, ear: .right) == entries)
    }

    @Test func aFullRightEarDropsItemsBeforeStatusGlyphs() {
        let big = NotchEarEntry(item: .stash, width: NotchGeometry.earRoom - 2 * side)
        let entries = NotchGeometry.withStatuses([.heat], side: side, before: [big, icon(.clipboard)])
        #expect(NotchGeometry.fit(entries, ear: .right).map(\.slot) == [.status(.heat), .item(.stash)])
    }

    @Test func anEarTooFullDropsItsFarEnd() {
        let big = NotchEarEntry(item: .system, width: NotchGeometry.earRoom - side)
        let entries = [big, icon(.stash), icon(.clipboard)]
        // On the right the far end is the last; on the left it is the first.
        #expect(NotchGeometry.fit(entries, ear: .right).map(\.item) == [.system])
        #expect(NotchGeometry.fit(entries, ear: .left).map(\.item) == [.stash, .clipboard])
        #expect(NotchGeometry.earWidth(NotchGeometry.fit(entries, ear: .right)) <= NotchGeometry.earRoom)
    }

    @Test func anItemWiderThanTheEarIsDroppedAlone() {
        #expect(NotchGeometry.fit([bars(NotchGeometry.earRoom + 1)], ear: .left).isEmpty)
    }

    @Test func readoutsShareTheirEarWithIcons() {
        let withIcons = NotchGeometry.readoutRoom([bars(0), icon(.clipboard), icon(.stash)])
        #expect(withIcons == NotchGeometry.earRoom - (2 * side + NotchGeometry.featureIconGap + NotchGeometry.barsGap))
        #expect(NotchGeometry.readoutRoom([bars(0)]) == NotchGeometry.earRoom)
        let full = (0..<8).map { _ in icon(.stash) } + [bars(0)]
        #expect(NotchGeometry.readoutRoom(full) == 0)
    }

    @Test func fewerReadoutsAreChosenWhenIconsTakeRoom() {
        let slots: [MenuBarSlot] = [.battery]
        let widths: [CGFloat] = [60]
        #expect(NotchGeometry.earReadouts(slots, widths: widths, room: 100) == [0])
        #expect(NotchGeometry.earReadouts(slots, widths: widths, room: 59).isEmpty)
    }
}
