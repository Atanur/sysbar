import AppKit

/// File URLs on a pasteboard, including the older filenames list Finder still writes.
enum ShelfPasteboard {
    static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static func containsFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(.fileURL) || types.contains(filenames)
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        guard containsFileURLs(pasteboard) else { return [] }
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }
        let names = pasteboard.propertyList(forType: filenames) as? [String] ?? []
        return names.map { URL(fileURLWithPath: $0) }
    }
}
