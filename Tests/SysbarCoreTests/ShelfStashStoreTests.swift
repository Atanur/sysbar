import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfStashStoreTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func makeStore() -> (ShelfStashStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (ShelfStashStore(directory: directory), directory)
    }

    @Test func aMissingFileIsTheFirstRunWithOnlyMain() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = store.load(now: now)
        #expect(loaded.isFirstRun)
        #expect(!loaded.recovered)
        #expect(loaded.library.stashes.count == 1)
    }

    @Test func aSavedLibraryComesBackAndTheFolderIsPrivate() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        var library = ShelfLibrary(now: now)
        let work = library.create(name: "Work", now: now) { "Stash \($0)" }
        library.add([ShelfItem.text("note", now: now)!], to: work, now: now)
        try store.save(library)

        let loaded = store.load(now: now)
        #expect(!loaded.isFirstRun)
        #expect(loaded.library == library)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }

    @Test func aDamagedFileIsMovedAsideNotDeleted() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(ShelfStashStore.fileName)
        try Data("{ not json".utf8).write(to: file)

        let loaded = store.load(now: now)
        #expect(loaded.recovered)
        #expect(!loaded.isFirstRun)
        #expect(loaded.library.stashes.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let asides = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(ShelfStashStore.corruptFilePrefix) }
        #expect(asides.count == 1)
        #expect(try Data(contentsOf: directory.appendingPathComponent(asides[0])) == Data("{ not json".utf8))
        // The next load is an ordinary empty one, and saving works again.
        try store.save(loaded.library)
        #expect(!store.load(now: now).recovered)
    }

    @Test func eachDamagedFileIsKeptNotOverwritten() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(ShelfStashStore.fileName)
        try Data("first".utf8).write(to: file)
        _ = store.load(now: now)
        try Data("second".utf8).write(to: file)
        _ = store.load(now: now)
        let asides = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(ShelfStashStore.corruptFilePrefix) }
        #expect(asides.count == 2)
    }

    @Test func oneDamagedStashOrItemCostsOnlyThat() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let good = "11111111-1111-1111-1111-111111111111"
        let json = """
        {"version":1,"stashes":[
         {"id":"\(good)","name":"Work","color":2,"created":1,"modified":1,"items":[
            {"id":"22222222-2222-2222-2222-222222222222","kind":"text","name":"a","path":"","text":"a","added":1},
            {"id":"nope"}]},
         {"name":"no id"}]}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent(ShelfStashStore.fileName))
        let loaded = store.load(now: now)
        #expect(!loaded.recovered)
        #expect(loaded.library.stashes.count == 2)
        #expect(loaded.library.stashes[1].name == "Work")
        #expect(loaded.library.stashes[1].items.map(\.text) == ["a"])
    }

    @Test func aNewerLayoutIsKeptAsideToo() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":99,"stashes":[]}"#.utf8).write(to: directory.appendingPathComponent(ShelfStashStore.fileName))
        #expect(store.load(now: now).recovered)
    }

    @Test func aFileWithoutMainIsRepairedOnLoad() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":1,"stashes":[]}"#.utf8).write(to: directory.appendingPathComponent(ShelfStashStore.fileName))
        let loaded = store.load(now: now)
        #expect(!loaded.recovered)
        #expect(loaded.library.main.isMain)
    }
}
