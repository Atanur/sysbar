import Foundation
import Testing
@testable import SysbarCore

@Suite struct StorageLocationTests {
    private let home = "/Users/someone"

    @Test func noStoredPathMeansTheDefaultFolder() {
        #expect(StorageLocation.parent(stored: "") == StorageLocation.defaultParent)
        #expect(StorageLocation.parent(stored: "   ") == StorageLocation.defaultParent)
    }

    @Test func aRelativeOrRootPathIsNotUsed() {
        #expect(StorageLocation.parent(stored: "Documents/Sysbar") == StorageLocation.defaultParent)
        #expect(StorageLocation.parent(stored: "/") == StorageLocation.defaultParent)
    }

    @Test func anAbsolutePathIsKeptAndTidied() {
        #expect(StorageLocation.parent(stored: "/Volumes/Data/./Sysbar/../Keep/") == URL(fileURLWithPath: "/Volumes/Data/Keep", isDirectory: true))
    }

    @Test func aTildeStandsForTheHomeFolder() {
        let expected = URL(fileURLWithPath: NSHomeDirectory() + "/Documents", isDirectory: true)
        #expect(StorageLocation.parent(stored: "~/Documents") == expected)
    }

    @Test func theDefaultFolderIsStoredAsNothing() {
        #expect(StorageLocation.storedValue(for: StorageLocation.defaultParent) == "")
        #expect(StorageLocation.storedValue(for: URL(fileURLWithPath: "/Volumes/Data/Keep")) == "/Volumes/Data/Keep")
    }

    @Test func theDefaultFoldersAreWhereTheDataAlwaysWas() {
        #expect(ClipboardStore.directory(parentStored: "") == ClipboardStore.standardDirectory)
        #expect(ShelfStashStore.directory(parentStored: "") == ShelfStashStore.standardDirectory)
    }

    @Test func dataGoesInAFolderOfItsOwnBelowTheChosenOne() {
        // A chosen folder such as Documents must never be the store itself: loading tidies its folder.
        let parent = "/Volumes/Data/Keep"
        #expect(ClipboardStore.directory(parentStored: parent).path == "/Volumes/Data/Keep/Clipboard")
        #expect(ShelfStashStore.directory(parentStored: parent).path == "/Volumes/Data/Keep/Stashes")
    }

    @Test func pathsAreShownFromTheHomeFolder() {
        #expect(StorageLocation.displayPath("/Users/someone/Library/Sysbar", home: home) == "~/Library/Sysbar")
        #expect(StorageLocation.displayPath("/Users/someone", home: home) == "~")
        #expect(StorageLocation.displayPath("/Users/someone2/x", home: home) == "/Users/someone2/x")
        #expect(StorageLocation.displayPath("/Volumes/Data", home: home) == "/Volumes/Data")
    }
}
