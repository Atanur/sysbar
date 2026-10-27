import Foundation

/// The name the user gives this Mac, shown on its tab in the popover instead of "This Mac".
public enum LocalDeviceName {
    /// Long enough for "Atanur's MacBook Pro", short enough for a tab.
    public static let maxLength = 32

    /// What is stored: trimmed and at most `maxLength` characters. Empty means the default name.
    public static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The stored name, or `fallback` when there is none.
    public static func display(_ stored: String?, fallback: String) -> String {
        let name = normalized(stored ?? "")
        return name.isEmpty ? fallback : name
    }
}
