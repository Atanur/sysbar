import CoreGraphics
import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfPickerLayoutTests {
    private let ids = (0..<5).map { _ in UUID() }

    @Test func everyStashGetsATileAndNewStashComesLast() {
        let layout = ShelfPickerLayout(stashes: Array(ids.prefix(2)))
        #expect(layout.tiles.count == 3)
        #expect(layout.tiles.last?.target == .newStash)
        #expect(layout.tiles.first?.target == .stash(ids[0]))
    }

    @Test func tilesFlowIntoRowsOfThree() {
        let layout = ShelfPickerLayout(stashes: ids)
        #expect(layout.tiles.count == 6)
        #expect(layout.tiles[2].frame.minY == layout.tiles[0].frame.minY)
        #expect(layout.tiles[3].frame.minY > layout.tiles[0].frame.maxY)
        #expect(layout.tiles[3].frame.minX == layout.tiles[0].frame.minX)
    }

    @Test func noTilesOverlapAndAllFitInside() {
        let layout = ShelfPickerLayout(stashes: ids, top: 40)
        let bounds = CGRect(origin: .zero, size: layout.size)
        for (index, tile) in layout.tiles.enumerated() {
            #expect(bounds.contains(tile.frame))
            #expect(tile.frame.minY >= 40)
            for other in layout.tiles[(index + 1)...] { #expect(!tile.frame.intersects(other.frame)) }
        }
    }

    @Test func aMinimumWidthCentresTheGrid() {
        let layout = ShelfPickerLayout(stashes: [], minWidth: 400)
        #expect(layout.size.width == 400)
        let tile = layout.tiles[0].frame
        #expect(abs(tile.midX - 200) < 0.001)
    }

    @Test func aPointFindsItsTileEvenInTheGapAndMissesOutsideTheGrid() {
        let layout = ShelfPickerLayout(stashes: Array(ids.prefix(2)))
        let first = layout.tiles[0].frame
        let second = layout.tiles[1].frame
        #expect(layout.target(at: CGPoint(x: first.midX, y: first.midY)) == .stash(ids[0]))
        #expect(layout.target(at: CGPoint(x: first.maxX + 2, y: first.midY)) == .stash(ids[0]))
        #expect(layout.target(at: CGPoint(x: second.maxX + 2, y: second.midY)) == .stash(ids[1]) || layout.target(at: CGPoint(x: second.maxX + 2, y: second.midY)) == .newStash)
        #expect(layout.target(at: CGPoint(x: 1, y: 1)) == nil)
        #expect(layout.target(at: CGPoint(x: -50, y: first.midY)) == nil)
    }
}
