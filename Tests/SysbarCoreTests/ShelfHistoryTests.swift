import Foundation
import Testing
@testable import SysbarCore

@Suite struct ShelfHistoryTests {
    private func record(_ paths: [String], _ seconds: TimeInterval) -> ShelfRecord {
        ShelfRecord(paths: paths, date: Date(timeIntervalSince1970: seconds))
    }

    @Test func theNewestShelfComesFirstAndAnEmptyOneIsIgnored() {
        let list = ShelfHistory.adding(record(["/b"], 2), to: [record(["/a"], 1)])
        #expect(list.map(\.paths) == [["/b"], ["/a"]])
        #expect(ShelfHistory.adding(record([], 3), to: list) == list)
    }

    @Test func theSameFilesReplaceTheOlderShelf() {
        let list = ShelfHistory.adding(record(["/b", "/a"], 3), to: [record(["/a", "/b"], 1), record(["/c"], 0)])
        #expect(list.map(\.paths) == [["/b", "/a"], ["/c"]])
    }

    @Test func onlyTheNewestAreKept() {
        var list: [ShelfRecord] = []
        for number in 0..<(ShelfHistory.limit + 5) { list = ShelfHistory.adding(record(["/\(number)"], Double(number)), to: list) }
        #expect(list.count == ShelfHistory.limit)
        #expect(list.first?.paths == ["/\(ShelfHistory.limit + 4)"])
    }
}
