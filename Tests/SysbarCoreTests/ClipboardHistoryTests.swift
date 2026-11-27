import Foundation
import Testing
@testable import SysbarCore

@Suite struct ClipboardKindTests {
    @Test func filesWinOverTheNamesFinderAlsoWritesAsText() {
        #expect(ClipboardKind.of(types: ["public.file-url", "public.utf8-plain-text"], text: "a.txt") == .files)
        #expect(ClipboardKind.of(types: ["NSFilenamesPboardType"], text: nil) == .files)
    }

    @Test func textIsPlainRichOrALink() {
        #expect(ClipboardKind.of(types: ["public.utf8-plain-text"], text: "hello") == .text)
        #expect(ClipboardKind.of(types: ["public.rtf", "public.utf8-plain-text"], text: "hello") == .richText)
        #expect(ClipboardKind.of(types: ["public.utf8-plain-text"], text: " https://example.com/a?b=1 \n") == .link)
        #expect(ClipboardKind.of(types: ["public.rtf", "public.utf8-plain-text"], text: "https://example.com") == .link)
    }

    @Test func anImageWithoutTextIsAnImage() {
        #expect(ClipboardKind.of(types: ["public.png"], text: nil) == .image)
        #expect(ClipboardKind.of(types: ["public.tiff"], text: "") == .image)
        #expect(ClipboardKind.of(types: ["public.png", "public.utf8-plain-text"], text: "caption") == .text)
    }

    @Test func blankTextOrUnknownTypesAreNotKept() {
        #expect(ClipboardKind.of(types: ["public.utf8-plain-text"], text: "  \n\t") == nil)
        #expect(ClipboardKind.of(types: ["com.example.private"], text: nil) == nil)
    }

    @Test func onlyASingleAddressWithAHostIsALink() {
        #expect(ClipboardKind.isLink("http://example.com"))
        #expect(ClipboardKind.isLink("mailto:someone@example.com"))
        #expect(!ClipboardKind.isLink("see https://example.com"))
        #expect(!ClipboardKind.isLink("example.com"))
        #expect(!ClipboardKind.isLink("https://"))
        #expect(!ClipboardKind.isLink("file:///etc/hosts"))
    }
}

@Suite struct ClipboardPrivacyTests {
    @Test func concealedAndTransientCopiesAreSkipped() {
        #expect(ClipboardPrivacy.isPrivate(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardPrivacy.isPrivate(types: ["org.nspasteboard.TransientType"]))
        #expect(ClipboardPrivacy.isPrivate(types: ["com.agilebits.onepassword"]))
        #expect(!ClipboardPrivacy.isPrivate(types: ["public.utf8-plain-text", "public.html"]))
    }
}

@Suite struct ClipboardHistoryTests {
    private func entry(_ text: String, _ seconds: TimeInterval = 0, kind: ClipboardKind = .text) -> ClipboardEntry {
        ClipboardEntry(kind: kind, text: text, fingerprint: ClipboardEntry.fingerprint(text: text), date: Date(timeIntervalSince1970: seconds))
    }

    @Test func theNewestComesFirstAndTheSameContentMovesUp() {
        let older = entry("a", 1)
        let list = ClipboardHistory.adding(entry("b", 2), to: [older], limit: 10).kept
        #expect(list.map(\.text) == ["b", "a"])
        let again = entry("a", 3)
        let change = ClipboardHistory.adding(again, to: list, limit: 10)
        #expect(change.kept.map(\.text) == ["a", "b"])
        #expect(change.kept.first?.id == again.id)
        #expect(change.dropped.map(\.id) == [older.id])
    }

    @Test func plainAndRichCopiesOfTheSameTextAreOneEntry() {
        let rich = entry("same", 1, kind: .richText)
        let change = ClipboardHistory.adding(entry("same", 2), to: [rich], limit: 10)
        #expect(change.kept.count == 1)
        #expect(change.kept.first?.kind == .text)
        #expect(change.dropped.map(\.id) == [rich.id])
    }

    @Test func onlyTheNewestAreKeptAndTheRestAreReported() {
        var list: [ClipboardEntry] = []
        var dropped: [ClipboardEntry] = []
        for number in 0..<7 {
            let change = ClipboardHistory.adding(entry("\(number)", Double(number)), to: list, limit: 5)
            list = change.kept
            dropped += change.dropped
        }
        #expect(list.map(\.text) == ["6", "5", "4", "3", "2"])
        #expect(dropped.map(\.text) == ["0", "1"])
    }

    @Test func aLowerLimitTrimsTheOldest() {
        let list = (0..<4).map { entry("\($0)") }
        let change = ClipboardHistory.trimmed(list, to: 2)
        #expect(change.kept.map(\.text) == ["0", "1"])
        #expect(change.dropped.map(\.text) == ["2", "3"])
    }

    @Test func promotingMovesAnEntryToTheTopWithANewDate() {
        let list = [entry("a", 1), entry("b", 2), entry("c", 3)]
        let promoted = ClipboardHistory.promoting(list[2].id, in: list, at: Date(timeIntervalSince1970: 9))
        #expect(promoted.map(\.text) == ["c", "a", "b"])
        #expect(promoted.first?.date == Date(timeIntervalSince1970: 9))
        #expect(ClipboardHistory.promoting(UUID(), in: list, at: Date()) == list)
    }

    @Test func searchIgnoresCaseAndAccentsAndLooksAtFileNames() {
        let file = ClipboardEntry(
            kind: .files, paths: ["/Users/me/Rapor Şubat.pdf"],
            fingerprint: ClipboardEntry.fingerprint(paths: ["/Users/me/Rapor Şubat.pdf"]), date: Date()
        )
        let list = [entry("Crème brûlée"), entry("Something else"), file]
        #expect(ClipboardHistory.matching("CREME", in: list).map(\.text) == ["Crème brûlée"])
        #expect(ClipboardHistory.matching("subat", in: list).map(\.id) == [file.id])
        // Only a file's name counts, not the folders it is in.
        #expect(ClipboardHistory.matching("users", in: list).isEmpty)
        #expect(ClipboardHistory.matching("  ", in: list) == list)
    }

    @Test func aPreviewIsOneShortLine() {
        #expect(ClipboardHistory.preview(of: "  first\n\n  second\tthird  ") == "first second third")
        let long = String(repeating: "x", count: 200)
        #expect(ClipboardHistory.preview(of: long, maxLength: 10) == String(repeating: "x", count: 10) + "…")
    }

    @Test func anUnknownLimitFallsBackToTheDefault() {
        #expect(ClipboardHistory.normalizedLimit(100) == 100)
        #expect(ClipboardHistory.normalizedLimit(7) == ClipboardHistory.defaultLimit)
        #expect(ClipboardHistory.normalizedLimit(nil) == ClipboardHistory.defaultLimit)
    }

    @Test func fingerprintsFollowTheContent() {
        #expect(ClipboardEntry.fingerprint(text: "a") == ClipboardEntry.fingerprint(text: "a"))
        #expect(ClipboardEntry.fingerprint(text: "a") != ClipboardEntry.fingerprint(text: "b"))
        #expect(ClipboardEntry.fingerprint(paths: ["/a", "/b"]) != ClipboardEntry.fingerprint(paths: ["/b", "/a"]))
        #expect(ClipboardEntry.fingerprint(data: Data([1, 2])) != ClipboardEntry.fingerprint(data: Data([2, 1])))
        // A file path is not the same thing as the same words copied as text.
        #expect(ClipboardEntry.fingerprint(paths: ["/a"]) != ClipboardEntry.fingerprint(text: "/a"))
    }
}

@Suite struct ClipboardStoreTests {
    private let store = ClipboardStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardStoreTests-\(UUID().uuidString)")
    )

    private func image(_ seconds: TimeInterval) -> ClipboardEntry {
        ClipboardEntry(kind: .image, fingerprint: "\(seconds)", date: Date(timeIntervalSince1970: seconds))
    }

    @Test func entriesAndTheirFilesSurviveASaveAndLoad() throws {
        defer { store.removeAll() }
        let text = ClipboardEntry(kind: .text, text: "hi", fingerprint: "t", source: "com.example", date: Date(timeIntervalSince1970: 1))
        let picture = image(2)
        try store.write(Data([7, 8, 9]), for: picture)
        try store.save([picture, text])
        #expect(store.load() == [picture, text])
        #expect(store.data(for: picture) == Data([7, 8, 9]))
        #expect(store.data(for: text) == nil)
    }

    @Test func anEntryWhoseFileIsGoneIsDroppedAndStrayFilesAreRemoved() throws {
        defer { store.removeAll() }
        let kept = image(1)
        let missing = image(2)
        let stray = image(3)
        try store.write(Data([1]), for: kept)
        try store.write(Data([3]), for: stray)
        try store.save([kept, missing])
        #expect(store.load() == [kept])
        #expect(store.data(for: stray) == nil)
    }

    @Test func anUnreadableIndexLeavesNoFilesBehind() throws {
        defer { store.removeAll() }
        let picture = image(1)
        try store.write(Data([1]), for: picture)
        try Data("not json".utf8).write(to: store.directory.appendingPathComponent("history.json"))
        #expect(store.load().isEmpty)
        #expect(store.data(for: picture) == nil)
    }

    @Test func removingEntriesDeletesTheirFiles() throws {
        defer { store.removeAll() }
        let picture = image(1)
        try store.write(Data([1]), for: picture)
        store.remove([picture])
        #expect(store.data(for: picture) == nil)
    }

    @Test func nothingSavedLoadsAsEmptyAndTheFolderIsPrivate() throws {
        defer { store.removeAll() }
        #expect(store.load().isEmpty)
        try store.save([])
        let attributes = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }
}

@Suite struct ClipboardFilterTests {
    private func entry(_ text: String, _ kind: ClipboardKind) -> ClipboardEntry {
        ClipboardEntry(kind: kind, text: text, fingerprint: ClipboardEntry.fingerprint(text: text + kind.rawValue), date: Date())
    }

    private let list: [ClipboardEntry]

    init() {
        let samples: [(String, ClipboardKind)] = [
            ("https://example.com/report", .link), ("report notes", .text),
            ("Formatted report", .richText), ("", .image), ("report.pdf", .files),
        ]
        list = samples.map { ClipboardEntry(kind: $0.1, text: $0.0, fingerprint: ClipboardEntry.fingerprint(text: $0.0 + $0.1.rawValue), date: Date()) }
    }

    @Test func richTextCountsAsText() {
        #expect(ClipboardFilter.text.includes(.text))
        #expect(ClipboardFilter.text.includes(.richText))
        #expect(!ClipboardFilter.text.includes(.link))
        #expect(ClipboardFilter.link.includes(.link))
        #expect(ClipboardFilter.image.includes(.image))
        #expect(ClipboardFilter.files.includes(.files))
    }

    @Test func everyKindBelongsToExactlyOneFilterBesidesAll() {
        for kind in ClipboardKind.allCases {
            let owners = ClipboardFilter.allCases.filter { $0 != .all && $0.includes(kind) }
            #expect(owners.count == 1)
            #expect(ClipboardFilter.all.includes(kind))
        }
    }

    @Test func aFilterKeepsOnlyItsKindsInOrder() {
        #expect(ClipboardHistory.matching("", filter: .all, in: list) == list)
        #expect(ClipboardHistory.matching("", filter: .text, in: list).map(\.kind) == [.text, .richText])
        #expect(ClipboardHistory.matching("", filter: .image, in: list).map(\.kind) == [.image])
    }

    @Test func theFilterAndTheSearchBothApply() {
        #expect(ClipboardHistory.matching("report", filter: .all, in: list).count == 4)
        #expect(ClipboardHistory.matching("REPORT", filter: .link, in: list).map(\.kind) == [.link])
        #expect(ClipboardHistory.matching("formatted", filter: .link, in: list).isEmpty)
    }

    @Test func onlyFiltersWithEntriesAreAvailable() {
        #expect(ClipboardHistory.availableFilters(in: []) == [.all])
        let some = [entry("a", .richText), entry("b", .files)]
        #expect(ClipboardHistory.availableFilters(in: some) == [.all, .text, .files])
        #expect(ClipboardHistory.availableFilters(in: list) == ClipboardFilter.allCases)
    }
}
