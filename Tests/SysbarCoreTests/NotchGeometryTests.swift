import CoreGraphics
import Testing
@testable import SysbarCore

@Suite struct NotchGeometryTests {
    /// A 16-inch MacBook Pro at "More Space", as measured: 220 × 38 pt notch, 39 pt menu bar.
    private let notched = NotchGeometry.make(
        frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1130),
        safeTop: 38,
        leftArea: CGRect(x: 0, y: 1131, width: 790, height: 38),
        rightArea: CGRect(x: 1010, y: 1131, width: 790, height: 38)
    )

    /// An external display with a 24 pt menu bar, placed right of the built-in one.
    private let plain = NotchGeometry.make(
        frame: CGRect(x: 1800, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1800, y: 0, width: 2560, height: 1416),
        safeTop: 0, leftArea: nil, rightArea: nil
    )

    @Test func theNotchIsMeasuredFromTheAreasBesideIt() {
        #expect(notched.shape == .notch)
        #expect(notched.anchor == CGRect(x: 790, y: 1131, width: 220, height: 38))
        #expect(notched.barHeight == 39)
    }

    @Test func aScreenWithoutANotchGetsACapsuleBelowTheTopEdge() {
        #expect(plain.shape == .capsule)
        #expect(plain.barHeight == 24)
        let capsule = plain.collapsedFrame(left: 100, right: 60)
        #expect(capsule.midX == plain.screen.midX)
        #expect(capsule.maxY == plain.screen.maxY - NotchGeometry.capsuleInset)
        #expect(capsule.height == 24 - 2 * NotchGeometry.capsuleInset)
        #expect(capsule.width == 100 + 60 + NotchGeometry.capsuleGap + 2 * NotchGeometry.earPadding)
    }

    @Test func earsSitEitherSideOfTheNotchAndCanBeLopsided() {
        let frame = notched.collapsedFrame(left: 80, right: 40)
        let left = 80 + NotchGeometry.earPadding
        let right = 40 + NotchGeometry.earPadding
        #expect(frame == CGRect(x: 790 - left, y: 1169 - 38, width: left + 220 + right, height: 38))
    }

    @Test func withNothingToShowOnlyTheNotchIsCovered() {
        #expect(notched.collapsedFrame(left: 0, right: 0) == notched.anchor)
    }

    @Test func anEarIsNeverWiderThanTheLimit() {
        let frame = notched.collapsedFrame(left: 900, right: 0)
        #expect(frame.minX == 790 - NotchGeometry.maxEarWidth)
    }

    @Test func theOpenPanelHangsFromTheTopEdgeCentredOnTheNotch() {
        let open = notched.expandedFrame(content: CGSize(width: 340, height: 500), collapsed: notched.collapsedFrame(left: 20, right: 20))
        #expect(open.maxY == 1169)
        #expect(open.midX == notched.anchor.midX)
        // The strip keeps the collapsed row, then the panel under it holds the content.
        #expect(open.height == 38 + 500 + NotchGeometry.contentInset)
        #expect(open.width == 340 + 2 * NotchGeometry.contentInset)
    }

    @Test func theOpenPanelIsAsWideAsItsContentWhenTheStripIsNarrower() {
        let strip = notched.collapsedFrame(left: 80, right: 40)
        let open = notched.expandedFrame(content: CGSize(width: 570, height: 300), collapsed: strip)
        #expect(open.width == 570 + 2 * NotchGeometry.contentInset)
        #expect(open.minX < strip.minX && open.maxX > strip.maxX)
        // The strip's top is the window's top, so the panel starts right under it.
        #expect(open.maxY == strip.maxY)
    }

    @Test func theOpenPanelIsAtLeastAsWideAsTheCollapsedRow() {
        let collapsed = notched.collapsedFrame(left: 300, right: 300)
        let open = notched.expandedFrame(content: CGSize(width: 340, height: 200), collapsed: collapsed)
        #expect(open.width == collapsed.width)
    }

    @Test func theOpenPanelStaysOnScreen() {
        let open = plain.expandedFrame(content: CGSize(width: 340, height: 5000), collapsed: plain.collapsedFrame(left: 60, right: 60))
        #expect(open.minY >= plain.screen.minY)
    }

    @Test func aHiddenMenuBarFallsBackToTheNotchOrAStandardHeight() {
        let hidden = NotchGeometry.make(
            frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
            safeTop: 38, leftArea: CGRect(x: 0, y: 1131, width: 790, height: 38), rightArea: CGRect(x: 1010, y: 1131, width: 790, height: 38)
        )
        #expect(hidden.barHeight == 38)
        let plainHidden = NotchGeometry.make(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeTop: 0, leftArea: nil, rightArea: nil
        )
        #expect(plainHidden.barHeight == NotchGeometry.standardBarHeight)
    }

    @Test func aNotchWithoutItsSideAreasIsTreatedAsACapsule() {
        let odd = NotchGeometry.make(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            safeTop: 32, leftArea: nil, rightArea: nil
        )
        #expect(odd.shape == .capsule)
    }

    @Test func theLeftEarKeepsTheBatteryAndFillsTheRestWithTheSystem() {
        let cpu = MenuBarSlot.metric(.cpu), gpu = MenuBarSlot.metric(.gpu), memory = MenuBarSlot.metric(.memory)
        #expect(NotchGeometry.earReadouts([]) == [])
        #expect(NotchGeometry.earReadouts([cpu, memory]) == [0, 1])
        #expect(NotchGeometry.earReadouts([.battery, cpu]) == [0, 1])
        // Three places in all: the battery takes one, wherever it is in the menu bar.
        #expect(NotchGeometry.earReadouts([cpu, memory, gpu, .battery]) == [0, 1, 3])
        #expect(NotchGeometry.earReadouts([.battery, cpu, memory, gpu]) == [0, 1, 2])
        // Without a battery the system has all three; the rest show once the island opens.
        let many = [cpu, gpu, memory, .metric(.power), .metric(.disk)]
        #expect(NotchGeometry.earReadouts(many) == [0, 1, 2])
    }

    @Test func featureIconsTakeASquareEachWithAGapBetween() {
        #expect(NotchGeometry.featureIconsWidth(0) == 0)
        #expect(NotchGeometry.featureIconsWidth(1) == NotchGeometry.featureIconSide)
        #expect(NotchGeometry.featureIconsWidth(4) == 4 * NotchGeometry.featureIconSide + 3 * NotchGeometry.featureIconGap)
        // Four icons and the padding still fit an ear.
        #expect(NotchGeometry.featureIconsWidth(4) + NotchGeometry.earPadding <= NotchGeometry.maxEarWidth)
    }

    @Test func thePickerHangsFromTheTopEdgeAtItsOwnSizeButKeepsBothEarsInside() {
        let collapsed = notched.collapsedFrame(left: 80, right: 40)
        let size = CGSize(width: 520, height: 150)
        let frame = notched.pickerFrame(size: size, collapsed: collapsed)
        #expect(frame.maxY == 1169)
        #expect(frame.size == size)
        #expect(frame.midX == notched.anchor.midX)
        // Narrower than the closed row: the row's width wins, so the layout is given it as its minimum.
        let narrow = notched.pickerFrame(size: CGSize(width: 100, height: 150), collapsed: collapsed)
        #expect(narrow.width == notched.minimumOpenWidth(collapsed))
        #expect(narrow.minX <= collapsed.minX && narrow.maxX >= collapsed.maxX)
    }
}
