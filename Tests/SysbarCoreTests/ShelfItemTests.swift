import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfItemTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func textBecomesALinkOnlyWhenItIsOneAddress() {
        #expect(ShelfItem.text("https://example.com/a")?.kind == .link)
        #expect(ShelfItem.text("see https://example.com")?.kind == .text)
        #expect(ShelfItem.text("  \n ") == nil)
    }

    @Test func aTextItemIsTitledByItsFirstLineAndClipped() {
        let item = ShelfItem.text("\n  First line  \nsecond")
        #expect(item?.name == "First line")
        #expect(item?.text == "First line  \nsecond")
        let long = ShelfItem.text(String(repeating: "a", count: 500))
        #expect(long?.name.count == ShelfItem.titleLimit)
        #expect(long?.text.count == 500)
    }

    @Test func fileKeysDifferByPathAndTextKeysByContent() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = ShelfItem.file(folder.appendingPathComponent("a.txt"))
        let b = ShelfItem.file(folder.appendingPathComponent("./a.txt"))
        #expect(a.key == b.key)
        #expect(a.key != ShelfItem.file(folder.appendingPathComponent("b.txt")).key)
        #expect(ShelfItem.text("x")!.key == ShelfItem.text("x")!.key)
        #expect(ShelfItem.text("x")!.key != ShelfItem.text("y")!.key)
    }

    @Test func aMovedAndRenamedFileIsFoundAgainByItsBookmark() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("report.txt")
        try "data".write(to: original, atomically: true, encoding: .utf8)
        let item = ShelfItem.file(original)
        #expect(item.bookmark != nil)

        let moved = folder.appendingPathComponent("archive", isDirectory: true).appendingPathComponent("final.txt")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: moved)

        let resolution = item.resolved()
        #expect(!resolution.isMissing)
        #expect(resolution.url?.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        #expect(resolution.item.name == "final.txt")
        #expect(resolution.item.path == resolution.url?.standardizedFileURL.path)
        #expect(resolution.item.id == item.id)
    }

    @Test func aDeletedFileIsMissingAndKeptAsItWas() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("gone.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let item = ShelfItem.file(file)
        try FileManager.default.removeItem(at: file)
        let resolution = item.resolved()
        #expect(resolution.isMissing)
        #expect(resolution.url == nil)
        #expect(resolution.item == item)
    }

    @Test func aFileWithoutABookmarkIsFoundByPathAndGetsOne() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.txt")
        // Added while the file was not there yet: no bookmark.
        var item = ShelfItem.file(file)
        #expect(item.bookmark == nil)
        try "x".write(to: file, atomically: true, encoding: .utf8)
        item = item.resolved().item
        #expect(item.bookmark != nil)
        #expect(!item.resolved().isMissing)
    }

    @Test func textResolvesToItselfAndIsNeverMissing() {
        let item = ShelfItem.text("hello")!
        let resolution = item.resolved()
        #expect(resolution.item == item)
        #expect(resolution.url == nil)
        #expect(!resolution.isMissing)
    }

    @Test func aFileInTheTrashCountsAsMissing() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let trash = folder.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let file = trash.appendingPathComponent("a.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(ShelfItem.file(file).resolved().isMissing)
    }
}
