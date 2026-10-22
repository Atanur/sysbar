import Foundation

/// Every user-facing string goes through here. `key` is the English text and must be a plain
/// literal (no interpolation) so `scripts/extract-strings.sh` can find it; values are passed as
/// `%@` arguments, numbered (`%1$@`, `%2$@`) when there is more than one so translations may
/// reorder them. Translations live in the app bundle's `<language>.lproj/Localizable.strings`;
/// where none exists (English, or the unit tests) the key itself is returned.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = LocalizationCache.shared.format(for: key)
    return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
}

/// The menu bar animation formats its labels many times a second, and a bundle lookup is far
/// slower than a dictionary read, so each key is looked up once. The language only changes on
/// relaunch, so entries never go stale.
private final class LocalizationCache: @unchecked Sendable {
    static let shared = LocalizationCache()

    private let lock = NSLock()
    private var formats: [String: String] = [:]

    func format(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = formats[key] { return cached }
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        formats[key] = format
        return format
    }
}
