import CoreGraphics
import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfFilesTests {
    @Test func onlyNewFilesAreShelved() {
        let held = [URL(fileURLWithPath: "/Library/Held.pdf")]
        let incoming = [
            URL(string: "https://example.com/a.pdf")!,
            URL(fileURLWithPath: "/Library/Report.pdf"),
            URL(fileURLWithPath: "/Library/Report.pdf"),
            URL(fileURLWithPath: "/Library/./Held.pdf"),
            URL(fileURLWithPath: "/Library/Notes"),
        ]
        #expect(ShelfFiles.worthShelving(incoming, alreadyHeld: held).map(\.path) == [
            "/Library/Report.pdf",
            "/Library/Notes",
        ])
    }

    @Test func aStraightDragIsNotAShake() {
        let path = (0..<6).map { DragShake.Sample(x: CGFloat($0) * 40, y: 10) }
        #expect(DragShake.reversals(path) == 0)
    }

    @Test func aTurnIsNotAShake() {
        let path = [
            DragShake.Sample(x: 0, y: 0),
            DragShake.Sample(x: 40, y: 0),
            DragShake.Sample(x: 40, y: 40),
        ]
        #expect(DragShake.reversals(path) == 0)
    }

    @Test func shakingBackAndForthSummonsTheShelf() {
        let path = [
            DragShake.Sample(x: 0, y: 0),
            DragShake.Sample(x: 30, y: 0),
            DragShake.Sample(x: 0, y: 2),
            DragShake.Sample(x: 30, y: 1),
            DragShake.Sample(x: 0, y: 0),
        ]
        #expect(DragShake.reversals(path) >= DragShake.reversalsNeeded)
    }

    @Test func theShelfSitsBesideThePointerAndStaysOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 72, height: 72)
        #expect(ShelfFiles.origin(size: size, near: CGPoint(x: 100, y: 400), visible: visible) == CGPoint(x: 128, y: 308))
        #expect(ShelfFiles.origin(size: size, near: CGPoint(x: 980, y: 10), visible: visible) == CGPoint(x: 880, y: 30))
    }

    @Test func aDefaultShelfSitsInItsCornerWithAMargin() {
        let visible = CGRect(x: 0, y: 20, width: 1000, height: 780)
        let size = CGSize(width: 100, height: 200)
        #expect(ShelfFiles.origin(size: size, placement: .topRight, visible: visible) == CGPoint(x: 888, y: 588))
        #expect(ShelfFiles.origin(size: size, placement: .bottomLeft, visible: visible) == CGPoint(x: 12, y: 32))
        #expect(ShelfFiles.origin(size: size, placement: .center, visible: visible) == CGPoint(x: 450, y: 310))
    }

    @Test func aGentlerShakeNeedsMoreMovement() {
        #expect(DragShake.Sensitivity.low.reversalsNeeded > DragShake.Sensitivity.standard.reversalsNeeded)
        #expect(DragShake.Sensitivity.standard.reversalsNeeded > DragShake.Sensitivity.high.reversalsNeeded)
        #expect(DragShake.Sensitivity.low.minTravel > DragShake.Sensitivity.high.minTravel)
    }

    @Test func aShortcutIsWrittenLikeMacOSWritesIt() {
        let shortcut = KeyShortcut(keyCode: 0, modifiers: (1 << 17) | (1 << 19), key: "A")
        #expect(shortcut.display == "⌥⇧A")
        #expect(shortcut.menuKey == "a")
        #expect(KeyShortcut(keyCode: 49, modifiers: 1 << 20, key: "Space").menuKey == " ")
        #expect(KeyShortcut(keyCode: 122, modifiers: 1 << 20, key: "F1").menuKey == nil)
    }

    @Test func theDefaultShakeCountsSmallSwingsThatLowIgnores() {
        let swings = (0..<6).map { DragShake.Sample(x: $0 % 2 == 0 ? 0 : 10, y: 0) }
        let standard = DragShake.Sensitivity.standard
        #expect(DragShake.reversals(swings, minTravel: standard.minTravel) >= standard.reversalsNeeded)
        #expect(DragShake.reversals(swings, minTravel: DragShake.Sensitivity.low.minTravel) == 0)
    }

    @Test func aSecondShelfGoesBesideTheFirstAndCascadesWhenThereIsNoRoom() {
        let size = CGSize(width: 100, height: 200)
        let wide = CGRect(x: 0, y: 20, width: 1000, height: 780)
        let first = CGRect(x: 888, y: 588, width: 100, height: 200)
        #expect(ShelfFiles.origin(size: size, placement: .topRight, visible: wide, avoiding: [first]) == CGPoint(x: 776, y: 588))
        #expect(ShelfFiles.origin(size: size, placement: .topLeft, visible: wide, avoiding: [CGRect(x: 12, y: 588, width: 100, height: 200)]) == CGPoint(x: 124, y: 588))

        let narrow = CGRect(x: 0, y: 0, width: 220, height: 400)
        let only = CGRect(x: 108, y: 188, width: 100, height: 200)
        #expect(ShelfFiles.origin(size: size, placement: .topRight, visible: narrow, avoiding: [only]) == CGPoint(x: 84, y: 164))
        #expect(ShelfFiles.origin(size: size, placement: .topRight, visible: narrow) == CGPoint(x: 108, y: 188))
    }

    @Test func aShelfPushedAgainstASideEdgeDocksThereButADefaultCornerDoesNot() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(ShelfFiles.dockEdge(of: CGRect(x: 0, y: 300, width: 176, height: 196), in: visible) == .left)
        #expect(ShelfFiles.dockEdge(of: CGRect(x: 824, y: 300, width: 176, height: 196), in: visible) == .right)
        #expect(ShelfFiles.dockEdge(of: CGRect(x: 812, y: 588, width: 176, height: 196), in: visible) == nil)
        #expect(ShelfFiles.dockEdge(of: CGRect(x: 400, y: 300, width: 176, height: 196), in: visible) == nil)
    }

    @Test func aDockedTabSitsFlushAtTheEdgeAndMakesRoomForAnother() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = ShelfFiles.dockFrame(edge: .left, in: visible, midY: 400)
        #expect(left == CGRect(x: -22, y: 310, width: 52, height: 180))
        let right = ShelfFiles.dockFrame(edge: .right, in: visible, midY: 400)
        #expect(right == CGRect(x: 970, y: 310, width: 52, height: 180))
        #expect(ShelfFiles.dockFrame(edge: .left, in: visible, midY: 400, avoiding: [left]).minY == 498)
        #expect(ShelfFiles.dockFrame(edge: .left, in: visible, midY: 5).minY == 8)
    }

    @Test func aTabOpensIntoAShelfBesideItsEdgeAtItsHeight() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 176, height: 196)
        #expect(ShelfFiles.undockedOrigin(edge: .left, size: size, in: visible, midY: 400) == CGPoint(x: 12, y: 302))
        #expect(ShelfFiles.undockedOrigin(edge: .right, size: size, in: visible, midY: 400) == CGPoint(x: 812, y: 302))
        #expect(ShelfFiles.undockedOrigin(edge: .left, size: size, in: visible, midY: 790).y == 592)
    }
}
