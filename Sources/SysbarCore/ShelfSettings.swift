import CoreGraphics
import Foundation

/// The key that opens the stash picker while it is held during a file drag.
public enum ShelfModifier: String, CaseIterable, Sendable {
    case shift, option, control, command
}

/// A global shortcut. `modifiers` holds `NSEvent.ModifierFlags` raw values (⇧ 1<<17, ⌃ 1<<18,
/// ⌥ 1<<19, ⌘ 1<<20); `key` is what to show for the key, such as "A" or "Space".
public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt
    public var key: String

    public init(keyCode: UInt16, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// "⌥⇧A": modifiers in the order macOS writes them, then the key.
    public var display: String {
        let glyphs: [(UInt, String)] = [(1 << 18, "⌃"), (1 << 19, "⌥"), (1 << 17, "⇧"), (1 << 20, "⌘")]
        return glyphs.filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
    }

    /// The key as a menu item's key equivalent, for the hint beside an item. Nil for keys a menu cannot show.
    public var menuKey: String? {
        if key == "Space" { return " " }
        return key.count == 1 ? key.lowercased() : nil
    }
}
