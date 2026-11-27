import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfLibraryTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func name(_ number: Int) -> String { "Stash \(number)" }
    private func note(_ text: String) -> ShelfItem { ShelfItem.text(text, now: now)! }

    @Test func aNewLibraryHasOnlyTheMainStash() {
        let library = ShelfLibrary(now: now)
        #expect(library.stashes.count == 1)
        #expect(library.main.isMain)
        #expect(library.main.id == ShelfStash.mainID)
    }

    @Test func newStashesGetUniqueDefaultNamesAndDistinctColours() {
        var library = ShelfLibrary(now: now)
        let first = library.create(now: now, defaultName: name)
        let second = library.create(now: now, defaultName: name)
        #expect(library.stash(first)?.name == "Stash 2")
        #expect(library.stash(second)?.name == "Stash 3")
        #expect(Set(library.stashes.map(\.color)).count == 3)
    }

    @Test func aDefaultNameSkipsOneThatIsTaken() {
        var library = ShelfLibrary(now: now)
        let id = library.create(name: "stash 2", now: now, defaultName: name)
        #expect(library.stash(id)?.name == "stash 2")
        let next = library.create(now: now, defaultName: name)
        #expect(library.stash(next)?.name == "Stash 3")
    }

    @Test func aGivenNameIsTrimmedAndAReservedOneIsNotUsed() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "  Work ", now: now, defaultName: name)
        #expect(library.stash(work)?.name == "Work")
        let clash = library.create(name: "Ana Zula", reserved: ["Ana Zula"], now: now, defaultName: name)
        #expect(library.stash(clash)?.name == "Stash 2")
    }

    @Test func coloursAreReusedOnlyOnceThePaletteIsUsedUp() {
        var library = ShelfLibrary(now: now)
        for _ in 0..<(ShelfStash.paletteSize - 1) { library.create(now: now, defaultName: name) }
        #expect(Set(library.stashes.map(\.color)).count == ShelfStash.paletteSize)
        library.create(now: now, defaultName: name)
        #expect(library.stashes.last?.color == 0)
    }

    @Test func renamingTrimsAndRefusesBlankTakenAndMain() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now, defaultName: name)
        let school = library.create(name: "School", now: now, defaultName: name)
        let renamed = library.rename(work, to: "  Office  ", now: now)
        #expect(renamed == .renamed)
        #expect(library.stash(work)?.name == "Office")
        let blank = library.rename(work, to: "   ", now: now)
        let taken = library.rename(work, to: "school", now: now)
        let same = library.rename(work, to: "Office", now: now)
        let reserved = library.rename(work, to: "Ana", reserved: ["ana"], now: now)
        let main = library.rename(school, to: "Main", now: now)
        let notAllowed = library.rename(ShelfStash.mainID, to: "Home", now: now)
        #expect(blank == .empty)
        #expect(taken == .taken)
        #expect(same == .unchanged)
        #expect(reserved == .taken)
        #expect(main == .taken)
        #expect(notAllowed == .notAllowed)
        #expect(library.stash(work)?.name == "Office")
    }

    @Test func recolouringWrapsIntoThePalette() {
        var library = ShelfLibrary(now: now)
        let id = library.create(now: now, defaultName: name)
        library.recolor(id, to: ShelfStash.paletteSize + 2, now: now)
        #expect(library.stash(id)?.color == 2)
        library.recolor(id, to: -1, now: now)
        #expect(library.stash(id)?.color == ShelfStash.paletteSize - 1)
    }

    @Test func addingSkipsWhatAStashHoldsAndReportsWhatWasAdded() {
        var library = ShelfLibrary(now: now)
        let one = note("one")
        let added = library.add([one, note("one"), note("two")], to: ShelfStash.mainID, now: now)
        let again = library.add([note("two")], to: ShelfStash.mainID, now: now)
        let unknown = library.add([one], to: UUID(), now: now)
        #expect(added.map(\.text) == ["one", "two"])
        #expect(again.isEmpty)
        #expect(unknown.isEmpty)
        #expect(library.main.items.count == 2)
    }

    @Test func theSameTextMayLiveInTwoStashes() {
        var library = ShelfLibrary(now: now)
        let other = library.create(now: now, defaultName: name)
        library.add([note("hello")], to: ShelfStash.mainID, now: now)
        let added = library.add([note("hello")], to: other, now: now)
        #expect(added.count == 1)
    }

    @Test func removingTakesItemsOutOfOneStash() {
        var library = ShelfLibrary(now: now)
        let items = [note("a"), note("b")]
        library.add(items, to: ShelfStash.mainID, now: now)
        library.remove([items[0].id], from: ShelfStash.mainID, now: now)
        #expect(library.main.items.map(\.text) == ["b"])
    }

    @Test func movingKeepsTheItemInTheTargetOnlyAndSkipsDuplicates() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now, defaultName: name)
        let items = [note("a"), note("b")]
        library.add(items, to: ShelfStash.mainID, now: now)
        library.add([note("b")], to: work, now: now)
        let moved = library.move(Set(items.map(\.id)), from: ShelfStash.mainID, to: work, now: now)
        #expect(moved == 2)
        #expect(library.main.items.isEmpty)
        #expect(library.stash(work)?.items.map(\.text) == ["b", "a"])
        let unknown = library.move([UUID()], from: work, to: ShelfStash.mainID, now: now)
        let sameStash = library.move(Set(items.map(\.id)), from: work, to: work, now: now)
        #expect(unknown == 0)
        #expect(sameStash == 0)
    }

    @Test func deletingMovesItemsToMainAndMainStays() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now, defaultName: name)
        library.add([note("a"), note("b")], to: work, now: now)
        library.add([note("a")], to: ShelfStash.mainID, now: now)
        let deleted = library.delete(work, now: now)
        #expect(deleted)
        #expect(library.stashes.count == 1)
        #expect(library.main.items.map(\.text) == ["a", "b"])
        let main = library.delete(ShelfStash.mainID, now: now)
        let unknown = library.delete(UUID(), now: now)
        #expect(!main)
        #expect(!unknown)
        #expect(library.stashes.count == 1)
    }

    @Test func updatingReplacesItemsByIdWhereverTheyAre() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now, defaultName: name)
        var item = note("a")
        library.add([item], to: work, now: now)
        item.name = "renamed"
        library.update([item])
        #expect(library.stash(work)?.items.first?.name == "renamed")
    }

    @Test func repairingKeepsMainFirstDropsRepeatsAndClampsColours() {
        let id = UUID()
        let broken = [
            ShelfStash(id: id, name: "  Work ", color: 99, items: [ShelfItem.text("a", now: now)!, ShelfItem.text("a", now: now)!], created: now),
            ShelfStash(id: id, name: "Again", color: 1, created: now),
            ShelfStash(name: "", color: 1, created: now),
        ]
        let library = ShelfLibrary.repaired(broken, now: now)
        #expect(library.stashes.count == 3)
        #expect(library.main.isMain)
        #expect(library.stashes[1].name == "Work")
        #expect(library.stashes[1].color == 99 % ShelfStash.paletteSize)
        #expect(library.stashes[1].items.count == 1)
        #expect(library.stashes[2].name == "Stash")
    }

    @Test func aRepeatedStashGivesItsItemsToTheFirst() {
        let id = UUID()
        let first = ShelfStash(id: id, name: "Work", color: 1, items: [ShelfItem.text("a", now: now)!], created: now)
        let again = ShelfStash(id: id, name: "Work", color: 1, items: [ShelfItem.text("a", now: now)!, ShelfItem.text("b", now: now)!], created: now)
        let secondMain = ShelfStash(id: ShelfStash.mainID, name: "Main", color: 0, items: [ShelfItem.text("m", now: now)!], created: now)
        let library = ShelfLibrary.repaired([first, again, secondMain, secondMain], now: now)
        #expect(library.stashes.count == 2)
        #expect(library.stashes[1].items.map(\.text) == ["a", "b"])
        #expect(library.main.items.map(\.text) == ["m"])
    }

    @Test func repairingKeepsTheMainStashItems() {
        var main = ShelfStash(id: ShelfStash.mainID, name: "Renamed", color: 3, items: [ShelfItem.text("keep", now: now)!], created: now)
        main.name = "Renamed"
        let library = ShelfLibrary.repaired([ShelfStash(name: "A", color: 1, created: now), main], now: now)
        #expect(library.main.items.count == 1)
        #expect(library.main.name == ShelfStash.mainName)
        #expect(library.main.color == 3)
        #expect(library.stashes.count == 2)
    }

    @Test func oldRecentShelvesGoToMainSkippingMissingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let kept = folder.appendingPathComponent("kept.txt")
        try "x".write(to: kept, atomically: true, encoding: .utf8)
        var library = ShelfLibrary(now: now)
        library.adopt([
            ShelfRecord(paths: [kept.path, folder.appendingPathComponent("gone.txt").path], date: now),
            ShelfRecord(paths: [kept.path], date: now.addingTimeInterval(-60)),
        ], now: now)
        #expect(library.main.items.map(\.name) == ["kept.txt"])
    }
}
