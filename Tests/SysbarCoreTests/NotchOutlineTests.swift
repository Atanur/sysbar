import CoreGraphics
import Testing

@testable import SysbarCore

struct NotchOutlineTests {
    private func outline(
        strip: ClosedRange<CGFloat> = 100...400, width: CGFloat = 500, room: CGFloat = 38, body: CGFloat = 300
    ) -> NotchOutline {
        NotchOutline(strip: strip, width: width, sideRoom: room, bodyHeight: body, bottomCorner: 32)
    }

    @Test func aPanelWiderThanTheStripGetsFilletsAndRoundedTopCorners() {
        let shape = outline()
        #expect(shape.left == NotchOutline.Side(fillet: NotchOutline.preferredFillet, corner: NotchOutline.preferredCorner))
        #expect(shape.right == shape.left)
        #expect(shape.bottom == 32)
    }

    @Test func aPanelAsWideAsTheStripIsStraightDown() {
        let shape = outline(strip: 0...500)
        #expect(shape.left == .none)
        #expect(shape.right == .none)
    }

    @Test func eachSideIsJudgedByItsOwnOverhang() {
        let shape = outline(strip: 0...400)
        #expect(shape.left == .none)
        #expect(shape.right.fillet > 0)
    }

    @Test func theCurvesNeverReachFartherThanTheRoomBesideTheStrip() {
        for overhang in stride(from: CGFloat(1), through: 80, by: 3) {
            let shape = outline(strip: overhang...(500 - overhang))
            let reach = (shape.left.fillet + shape.left.corner) * NotchOutline.continuousReach
            #expect(reach <= overhang + 0.001)
        }
    }

    @Test func aFilletStaysWithinTheStripsStraightSide() {
        let shape = outline(room: 11)
        #expect(shape.left.fillet * NotchOutline.continuousReach <= 11 + 0.001)
    }

    @Test func aPanelThatIsOnlyStartingToOpenIsAPlainStrip() {
        #expect(outline(body: 0).left == .none)
        #expect(outline(body: 0).bottom == 0)
        let small = outline(body: 10)
        #expect(small.left.fillet <= 5 && small.left.corner <= 5 && small.bottom <= 5)
    }

    @Test func theBottomCornersNeverExceedHalfTheWidth() {
        #expect(outline(strip: 0...40, width: 40).bottom == 20)
    }
}
