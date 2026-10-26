import Foundation
import Testing
@testable import SysbarCore

@Suite struct ChangelogTests {
    private let markdown = """
        # Changelog

        Intro text that is not a release.

        ## 0.5.3 — 2026-10-27

        - A bolt on the **Power** card.
        - Shares under 10% keep `one` decimal.

        ## 0.5.2 — 2026-10-27

        * Per-app CPU over all cores,
          continued on a second line.

        ## Unreleased

        - Not a version, so it is skipped.
        """

    @Test func readsEachVersionWithItsDateAndItems() {
        let releases = Changelog.parse(markdown)

        #expect(releases.map(\.version.description) == ["0.5.3", "0.5.2"])
        #expect(releases.first?.date == "2026-10-27")
        #expect(releases.first?.items == ["A bolt on the Power card.", "Shares under 10% keep one decimal."])
    }

    @Test func joinsAnItemThatWrapsOntoTheNextLine() {
        #expect(Changelog.parse(markdown).last?.items == ["Per-app CPU over all cores, continued on a second line."])
    }

    @Test func findsTheNotesOfOneVersion() {
        let releases = Changelog.parse(markdown)

        #expect(Changelog.release(AppVersion("0.5.2"), in: releases)?.items.count == 1)
        #expect(Changelog.release(AppVersion("9.9.9"), in: releases) == nil)
        #expect(Changelog.release(nil, in: releases) == nil)
    }

    @Test func readsTheBulletsOfAGitHubReleaseBody() {
        let body = "- First change\r\n- Second **change**\r\n\r\n**Full Changelog**: https://github.com/x/y/compare/a...b"

        #expect(Changelog.items(in: body) == ["First change", "Second change"])
    }

    @Test func keepsAtMostTheItemsAskedFor() {
        let body = (1...9).map { "- Item \($0)" }.joined(separator: "\n")

        #expect(Changelog.items(in: body, limit: 3) == ["Item 1", "Item 2", "Item 3"])
    }

    @Test func emptyOrPlainTextHasNoItems() {
        #expect(Changelog.parse("").isEmpty)
        #expect(Changelog.items(in: "Just a sentence.").isEmpty)
    }

    /// The file shipped in the app must parse, newest first, with notes for every release.
    @Test func theProjectChangelogIsWellFormed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CHANGELOG.md")
        let releases = Changelog.parse(try String(contentsOf: url, encoding: .utf8))

        #expect(!releases.isEmpty)
        #expect(releases.allSatisfy { !$0.items.isEmpty && $0.date != nil })
        #expect(zip(releases, releases.dropFirst()).allSatisfy { $0.version > $1.version })
    }
}
