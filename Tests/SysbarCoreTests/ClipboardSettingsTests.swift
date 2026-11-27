import Foundation
import Testing
@testable import SysbarCore

@Suite struct ClipboardRetentionTests {
    private let now = Date(timeIntervalSince1970: 10_000_000)

    private func entry(_ id: Int, daysOld: Double) -> ClipboardEntry {
        ClipboardEntry(kind: .text, text: "\(id)", fingerprint: "\(id)", date: now.addingTimeInterval(-daysOld * 86_400))
    }

    @Test func eachChoiceHasItsLength() {
        #expect(ClipboardRetention.day.seconds == 86_400)
        #expect(ClipboardRetention.week.seconds == 7 * 86_400.0)
        #expect(ClipboardRetention.month.seconds == 30 * 86_400.0)
        #expect(ClipboardRetention.quarter.seconds == 90 * 86_400.0)
        #expect(ClipboardRetention.forever.seconds == nil)
    }

    @Test func anUnknownOrMissingChoiceIsForever() {
        #expect(ClipboardRetention.normalized(nil) == .forever)
        #expect(ClipboardRetention.normalized("fortnight") == .forever)
        #expect(ClipboardRetention.normalized("week") == .week)
    }

    @Test func entriesOlderThanTheChoiceGo() {
        let list = [entry(1, daysOld: 0.5), entry(2, daysOld: 2), entry(3, daysOld: 10)]
        let day = ClipboardHistory.expired(list, keeping: .day, now: now)
        #expect(day.kept.map(\.text) == ["1"])
        #expect(day.dropped.map(\.text) == ["2", "3"])
        let week = ClipboardHistory.expired(list, keeping: .week, now: now)
        #expect(week.kept.map(\.text) == ["1", "2"])
        #expect(week.dropped.map(\.text) == ["3"])
    }

    @Test func foreverKeepsEverything() {
        let list = [entry(1, daysOld: 4000)]
        let result = ClipboardHistory.expired(list, keeping: .forever, now: now)
        #expect(result.kept == list)
        #expect(result.dropped.isEmpty)
    }

    @Test func anEntryExactlyAsOldAsTheChoiceIsKept() {
        let list = [entry(1, daysOld: 1)]
        #expect(ClipboardHistory.expired(list, keeping: .day, now: now).kept == list)
    }

    @Test func aRecopiedEntryCountsFromItsLastCopy() {
        let old = entry(1, daysOld: 40)
        let promoted = ClipboardHistory.promoting(old.id, in: [old], at: now)
        #expect(ClipboardHistory.expired(promoted, keeping: .week, now: now).dropped.isEmpty)
    }
}

@Suite struct ClipboardRecordingTests {
    @Test func nothingStoredRecordsEveryKind() {
        #expect(ClipboardRecording.normalized(stored: nil) == Set(ClipboardKind.allCases))
    }

    @Test func storedKindsAreReadBackAndUnknownOnesIgnored() {
        #expect(ClipboardRecording.normalized(stored: ["text", "files", "sound"]) == [.text, .files])
        #expect(ClipboardRecording.normalized(stored: []) == [])
        #expect(ClipboardRecording.normalized(stored: ["sound"]) == Set(ClipboardKind.allCases))
        #expect(ClipboardRecording.stored([.files, .text]) == ["text", "files"])
    }

    @Test func aKindThatIsAllowedIsKeptAsItself() {
        for kind in ClipboardKind.allCases {
            #expect(ClipboardRecording.kept(kind, allowed: Set(ClipboardKind.allCases)) == kind)
        }
    }

    @Test func richTextWithoutItsFormattingIsPlainText() {
        #expect(ClipboardRecording.kept(.richText, allowed: [.text]) == .text)
        #expect(ClipboardRecording.kept(.richText, allowed: [.image]) == nil)
    }

    @Test func linksImagesAndFilesAreSkippedWhenTurnedOff() {
        #expect(ClipboardRecording.kept(.link, allowed: [.text]) == nil)
        #expect(ClipboardRecording.kept(.image, allowed: [.text]) == nil)
        #expect(ClipboardRecording.kept(.files, allowed: [.text]) == nil)
        #expect(ClipboardRecording.kept(.text, allowed: []) == nil)
    }
}

@Suite struct ClipboardLimitsTests {
    @Test func imageSizesAreChosenInMegabytes() {
        #expect(ClipboardHistory.imageLimits == [5, 10, 20, 50])
        #expect(ClipboardHistory.normalizedImageLimit(nil) == 20)
        #expect(ClipboardHistory.normalizedImageLimit(7) == 20)
        #expect(ClipboardHistory.normalizedImageLimit(50) == 50)
        #expect(ClipboardHistory.imageBytes(megabytes: 10) == 10_000_000)
        #expect(ClipboardHistory.maxImageBytes == ClipboardHistory.imageBytes(megabytes: 20))
    }

    @Test func aRepeatedCopyMovesUpUnlessRepeatsAreKept() {
        let first = ClipboardEntry(kind: .text, text: "a", fingerprint: "a", date: Date(timeIntervalSince1970: 1))
        let again = ClipboardEntry(kind: .text, text: "a", fingerprint: "a", date: Date(timeIntervalSince1970: 2))
        let merged = ClipboardHistory.adding(again, to: [first], limit: 10)
        #expect(merged.kept == [again])
        #expect(merged.dropped == [first])
        let repeated = ClipboardHistory.adding(again, to: [first], limit: 10, keepingDuplicates: true)
        #expect(repeated.kept == [again, first])
        #expect(repeated.dropped.isEmpty)
        let limited = ClipboardHistory.adding(again, to: [first], limit: 1, keepingDuplicates: true)
        #expect(limited.kept == [again])
        #expect(limited.dropped == [first])
    }
}

@Suite struct ClipboardStoreLocationTests {
    private func makeStore() -> ClipboardStore {
        ClipboardStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardMove-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true))
    }

    private func clean(_ stores: ClipboardStore...) {
        stores.forEach { try? FileManager.default.removeItem(at: $0.directory.deletingLastPathComponent()) }
    }

    private func image(_ seconds: TimeInterval) -> ClipboardEntry {
        ClipboardEntry(kind: .image, fingerprint: "\(seconds)", date: Date(timeIntervalSince1970: seconds))
    }

    @Test func sizeOnDiskAddsUpTheFiles() throws {
        let store = makeStore()
        defer { clean(store) }
        #expect(store.sizeOnDisk() == 0)
        let picture = image(1)
        try store.write(Data(repeating: 1, count: 1_000), for: picture)
        try store.save([picture])
        #expect(store.sizeOnDisk() >= 1_000)
    }

    @Test func loadingLeavesFilesThatAreNotItsOwnAlone() throws {
        let store = makeStore()
        defer { clean(store) }
        let kept = image(1)
        try store.write(Data([1]), for: kept)
        try store.save([kept])
        let foreign = store.directory.appendingPathComponent("holiday.jpg")
        try Data([9]).write(to: foreign)
        #expect(store.load() == [kept])
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }

    @Test func movingCarriesTheHistoryAndLeavesNothingBehind() throws {
        let source = makeStore()
        let target = makeStore()
        defer { clean(source, target) }
        let picture = image(1)
        let text = ClipboardEntry(kind: .text, text: "hi", fingerprint: "t", date: Date(timeIntervalSince1970: 2))
        try source.write(Data([4, 5]), for: picture)
        try source.save([text, picture])

        try source.moved(to: target)

        #expect(target.load() == [text, picture])
        #expect(target.data(for: picture) == Data([4, 5]))
        #expect(!FileManager.default.fileExists(atPath: source.directory.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: target.directory.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
    }

    @Test func movingNeverOverwritesAHistoryThatIsAlreadyThere() throws {
        let source = makeStore()
        let target = makeStore()
        defer { clean(source, target) }
        let mine = ClipboardEntry(kind: .text, text: "mine", fingerprint: "m", date: Date(timeIntervalSince1970: 1))
        let theirs = ClipboardEntry(kind: .text, text: "theirs", fingerprint: "t", date: Date(timeIntervalSince1970: 2))
        try source.save([mine])
        try target.save([theirs])

        #expect(throws: StorageMoveError.destinationHasData) { try source.moved(to: target) }
        #expect(source.load() == [mine])
        #expect(target.load() == [theirs])
        #expect(target.hasHistory)
    }

    @Test func movingFromAFolderThatHoldsNothingJustSucceeds() throws {
        let source = makeStore()
        let target = makeStore()
        defer { clean(source, target) }
        try source.moved(to: target)
        #expect(!target.hasHistory)
    }
}
