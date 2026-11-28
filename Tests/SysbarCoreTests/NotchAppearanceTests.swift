import CoreGraphics
import Testing
@testable import SysbarCore

@Suite struct NotchDisplayChoiceTests {
    private let builtIn = NotchDisplay(id: 1, isBuiltIn: true)
    private let external = NotchDisplay(id: 2, isBuiltIn: false)
    private let other = NotchDisplay(id: 3, isBuiltIn: false)

    @Test func builtInOnlyPicksTheBuiltInDisplay() {
        let chosen = NotchDisplayChoice.builtIn.select(from: [external, builtIn], primary: 2, active: 2)
        #expect(chosen == [1])
    }

    @Test func builtInOnlyFallsBackToThePrimaryDisplayWhenThereIsNoBuiltInOne() {
        // A desktop Mac, or a laptop with its lid closed: something still shows.
        #expect(NotchDisplayChoice.builtIn.select(from: [external, other], primary: 3, active: 2) == [3])
        #expect(NotchDisplayChoice.builtIn.select(from: [external, other], primary: nil, active: nil) == [2])
    }

    @Test func allDisplaysGetOneEach() {
        #expect(NotchDisplayChoice.all.select(from: [builtIn, external, other], primary: 1, active: 1) == [1, 2, 3])
    }

    @Test func theActiveMenuBarDisplayFollowsTheActiveOne() {
        let screens = [builtIn, external]
        #expect(NotchDisplayChoice.active.select(from: screens, primary: 1, active: 2) == [2])
        #expect(NotchDisplayChoice.active.select(from: screens, primary: 1, active: 1) == [1])
    }

    @Test func anActiveDisplayThatIsGoneFallsBackToThePrimaryThenTheFirst() {
        let screens = [builtIn, external]
        #expect(NotchDisplayChoice.active.select(from: screens, primary: 2, active: 9) == [2])
        #expect(NotchDisplayChoice.active.select(from: screens, primary: nil, active: nil) == [1])
    }

    @Test func noDisplaysMeansNoIslands() {
        for choice in NotchDisplayChoice.allCases {
            #expect(choice.select(from: [], primary: nil, active: nil).isEmpty)
        }
    }
}

@Suite struct NotchBackgroundTests {
    @Test func automaticIsBlackAroundTheNotchAndGlassOnACapsule() {
        #expect(NotchBackground.automatic.fill(for: .notch) == .black)
        #expect(NotchBackground.automatic.fill(for: .capsule) == .glass)
    }

    @Test func aChosenStyleAppliesToBothShapes() {
        for shape in [NotchGeometry.Shape.notch, .capsule] {
            #expect(NotchBackground.black.fill(for: shape) == .black)
            #expect(NotchBackground.glass.fill(for: shape) == .glass)
        }
    }

    @Test func onlyBlackIsAlwaysDark() {
        #expect(NotchBackground.Fill.black.isDark)
        #expect(!NotchBackground.Fill.glass.isDark)
    }

    @Test func aStoredValueIsReadBackAndAnythingElseIsAutomatic() {
        for background in NotchBackground.allCases {
            #expect(NotchBackground.stored(background.rawValue) == background)
        }
        #expect(NotchBackground.stored(nil) == .automatic)
        #expect(NotchBackground.stored("nonsense") == .automatic)
    }

    @Test func theRemovedTransparentStyleBecomesAutomatic() {
        #expect(NotchBackground.stored("transparent") == .automatic)
        #expect(NotchBackground.stored("clear") == .automatic)
    }
}

@Suite struct NotchIconSizeTests {
    @Test func mediumIsTheCurrentSize() {
        #expect(NotchIconSize.medium.scale == 1)
        #expect(NotchGeometry.featureIconSide(scale: 1) == NotchGeometry.featureIconSide)
    }

    @Test func sizesGrowInOrder() {
        #expect(NotchIconSize.small.scale < NotchIconSize.medium.scale)
        #expect(NotchIconSize.medium.scale < NotchIconSize.large.scale)
    }

    @Test func contentNeverGrowsPastTheRowItSitsIn() {
        // A capsule on a 24 pt menu bar is 22 pt tall, which holds the 22 pt readouts and no more.
        #expect(NotchGeometry.contentScale(.large, rowHeight: 22) == 1)
        #expect(NotchGeometry.contentScale(.small, rowHeight: 22) == NotchIconSize.small.scale)
        // A notch is taller, so large fits.
        #expect(NotchGeometry.contentScale(.large, rowHeight: 38) == NotchIconSize.large.scale)
    }

    @Test func iconSidesFollowTheScale() {
        #expect(NotchGeometry.featureIconSide(scale: 1.15) == (22 * 1.15).rounded())
        #expect(NotchGeometry.featureIconsWidth(2, side: 26) == 2 * 26 + NotchGeometry.featureIconGap)
    }
}

@Suite struct NotchEarContentTests {
    private let cpu = MenuBarSlot.metric(.cpu), gpu = MenuBarSlot.metric(.gpu), memory = MenuBarSlot.metric(.memory)
    private let power = MenuBarSlot.metric(.power)

    @Test func theLimitSetsHowManyReadoutsShow() {
        let slots = [cpu, gpu, memory, power]
        #expect(NotchGeometry.earReadouts(slots, limit: 4) == [0, 1, 2, 3])
        #expect(NotchGeometry.earReadouts(slots, limit: 1) == [0])
        #expect(NotchGeometry.earReadouts(slots, limit: 0) == [])
    }

    @Test func theBatteryKeepsItsPlaceWhateverTheLimit() {
        #expect(NotchGeometry.earReadouts([cpu, gpu, .battery], limit: 1) == [2])
        #expect(NotchGeometry.earReadouts([cpu, gpu, .battery], limit: 2) == [0, 2])
    }

    @Test func readoutsThatWouldOverflowTheEarStayInThePanel() {
        let room = NotchGeometry.maxEarWidth - NotchGeometry.earPadding
        let slots = [cpu, gpu, memory, power]
        let widths: [CGFloat] = [room / 2, room / 2, 30, 30]
        // Two take the room less one gap; the third does not fit.
        let narrow = NotchGeometry.earReadouts(slots, limit: 4, widths: widths, gap: 10)
        #expect(narrow == [0])
        let slim: [CGFloat] = [40, 40, 40, 40]
        #expect(NotchGeometry.earReadouts(slots, limit: 4, widths: slim, gap: 10) == [0, 1, 2])
        // 3 × 40 + 2 × 10 = 140 fits in 156; a fourth would make 190.
        #expect(140 <= room && 190 > room)
    }

    @Test func aBatteryThatFitsIsKeptBeforeTheOthersAreCounted() {
        let slots = [cpu, gpu, .battery]
        let room = NotchGeometry.maxEarWidth - NotchGeometry.earPadding
        let widths: [CGFloat] = [room - 40, room - 40, 60]
        #expect(NotchGeometry.earReadouts(slots, limit: 3, widths: widths, gap: 10) == [2])
    }

    @Test func aCapsuleRowOnlyKeepsAGapBetweenTwoHalves() {
        #expect(NotchGeometry.capsuleRowWidth(left: 100, right: 60) == 100 + 60 + NotchGeometry.capsuleGap)
        #expect(NotchGeometry.capsuleRowWidth(left: 100, right: 0) == 100)
        #expect(NotchGeometry.capsuleRowWidth(left: 0, right: 60) == 60)
        #expect(NotchGeometry.capsuleRowWidth(left: 0, right: 0) == 0)
    }

    @Test func anEmptyCapsuleIsStillAUsableTarget() {
        let plain = NotchGeometry.make(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
            safeTop: 0, leftArea: nil, rightArea: nil
        )
        let empty = plain.collapsedFrame(left: 0, right: 0)
        #expect(empty.width == NotchGeometry.capsuleMinimumWidth)
        #expect(empty.midX == plain.screen.midX)
    }

    @Test func aBareNotchHasNoEars() {
        let notched = NotchGeometry.make(
            frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1130),
            safeTop: 38, leftArea: CGRect(x: 0, y: 1131, width: 790, height: 38), rightArea: CGRect(x: 1010, y: 1131, width: 790, height: 38)
        )
        #expect(notched.collapsedFrame(left: 0, right: 0) == notched.anchor)
    }
}
