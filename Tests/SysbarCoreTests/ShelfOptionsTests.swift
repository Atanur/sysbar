import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfDeleteOptionTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func library() -> (ShelfLibrary, ShelfStash.ID) {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now) { "Stash \($0)" }
        library.add([ShelfItem.text("note", now: now)!], to: work, now: now)
        return (library, work)
    }

    @Test func deletingCanDropTheItemsWithTheStash() {
        var (library, work) = library()
        let deleted = library.delete(work, movingItemsToMain: false, now: now)
        #expect(deleted)
        #expect(library.stash(work) == nil)
        #expect(library.itemCount == 0)
    }

    @Test func deletingMovesTheItemsToMainByDefault() {
        var (library, work) = library()
        let deleted = library.delete(work, now: now)
        #expect(deleted)
        #expect(library.main.items.count == 1)
    }

    @Test func mainCannotBeDeletedEitherWay() {
        var (library, _) = library()
        let deleted = library.delete(ShelfStash.mainID, movingItemsToMain: false, now: now)
        #expect(!deleted)
    }
}

@Suite struct ShelfDefaultStashTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func theChosenStashWinsWhileItExists() {
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now) { "Stash \($0)" }
        let school = library.create(name: "School", now: now) { "Stash \($0)" }
        #expect(ShelfDefaultStash.target(chosen: work, lastUsed: school, in: library) == work)
    }

    @Test func noChoiceUsesTheLastUsedStash() {
        var library = ShelfLibrary(now: now)
        let school = library.create(name: "School", now: now) { "Stash \($0)" }
        #expect(ShelfDefaultStash.target(chosen: nil, lastUsed: school, in: library) == school)
    }

    @Test func aDeletedStashFallsBackToTheLastUsedThenMain() {
        var library = ShelfLibrary(now: now)
        let school = library.create(name: "School", now: now) { "Stash \($0)" }
        #expect(ShelfDefaultStash.target(chosen: UUID(), lastUsed: school, in: library) == school)
        #expect(ShelfDefaultStash.target(chosen: UUID(), lastUsed: UUID(), in: library) == ShelfStash.mainID)
    }

    @Test func aStoredIdIsReadBackOrIgnored() {
        let id = UUID()
        #expect(ShelfDefaultStash.chosen(stored: id.uuidString) == id)
        #expect(ShelfDefaultStash.chosen(stored: "") == nil)
        #expect(ShelfDefaultStash.chosen(stored: "nonsense") == nil)
    }
}

@Suite struct ShelfStashStoreMoveTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func makeStore() -> ShelfStashStore {
        ShelfStashStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("StashMove-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Stashes", isDirectory: true))
    }

    private func clean(_ stores: ShelfStashStore...) {
        stores.forEach { try? FileManager.default.removeItem(at: $0.directory.deletingLastPathComponent()) }
    }

    @Test func movingCarriesTheStashesAndRemovesTheOldFile() throws {
        let source = makeStore()
        let target = makeStore()
        defer { clean(source, target) }
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now) { "Stash \($0)" }
        library.add([ShelfItem.text("note", now: now)!], to: work, now: now)
        try source.save(library)

        try source.moved(to: target)

        let loaded = target.load(now: now)
        #expect(!loaded.isFirstRun)
        #expect(loaded.library == library)
        #expect(!source.hasStashes)
        #expect(!FileManager.default.fileExists(atPath: source.directory.path))
    }

    @Test func movingNeverOverwritesStashesThatAreAlreadyThere() throws {
        let source = makeStore()
        let target = makeStore()
        defer { clean(source, target) }
        try source.save(ShelfLibrary(now: now))
        var other = ShelfLibrary(now: now)
        other.create(name: "Other", now: now) { "Stash \($0)" }
        try target.save(other)

        #expect(throws: StorageMoveError.destinationHasData) { try source.moved(to: target) }
        #expect(source.hasStashes)
        #expect(target.load(now: now).library == other)
    }
}
