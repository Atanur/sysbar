import CoreGraphics
import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfFilesTests {
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

    @Test func shakingBackAndForthOpensThePicker() {
        let path = [
            DragShake.Sample(x: 0, y: 0),
            DragShake.Sample(x: 30, y: 0),
            DragShake.Sample(x: 0, y: 2),
            DragShake.Sample(x: 30, y: 1),
            DragShake.Sample(x: 0, y: 0),
        ]
        #expect(DragShake.reversals(path) >= DragShake.reversalsNeeded)
    }

    @Test func thePanelSitsBesideThePointerAndStaysOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 72, height: 72)
        #expect(ShelfFiles.origin(size: size, near: CGPoint(x: 100, y: 400), visible: visible) == CGPoint(x: 128, y: 308))
        #expect(ShelfFiles.origin(size: size, near: CGPoint(x: 980, y: 10), visible: visible) == CGPoint(x: 880, y: 30))
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
}
