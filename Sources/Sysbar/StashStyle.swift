import AppKit
import SwiftUI
import SysbarCore

/// How a stash looks and is named: a tint from a fixed palette, so stashes tell apart by colour as
/// well as by name, and the name VoiceOver and the colour menu use for each tint.
enum StashStyle {
    private static let tints: [NSColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemRed, .systemYellow,
    ]

    static func nsColor(_ index: Int) -> NSColor { tints[ShelfStash.clamped(index)] }
    static func color(_ index: Int) -> Color { Color(nsColor: nsColor(index)) }

    /// The tint's name; a literal switch so the strings are found for translation.
    static func colorName(_ index: Int) -> String {
        switch ShelfStash.clamped(index) {
        case 0: L("Blue")
        case 1: L("Green")
        case 2: L("Orange")
        case 3: L("Pink")
        case 4: L("Purple")
        case 5: L("Teal")
        case 6: L("Red")
        default: L("Yellow")
        }
    }
}

extension ShelfStash {
    /// The name to show: the main stash is localized, the others are the user's own words.
    var displayName: String { isMain ? L("Main") : name }
    var tint: Color { StashStyle.color(color) }
    /// "1 item", "3 items".
    var countText: String { items.count == 1 ? L("1 item") : L("%@ items", "\(items.count)") }
}

/// A stash's colour dot, followed by its name, used wherever a stash is listed.
struct StashLabel: View {
    let stash: ShelfStash
    var showsCount = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(stash.tint).frame(width: 9, height: 9).accessibilityHidden(true)
            Text(stash.displayName).lineLimit(1).truncationMode(.tail)
            if showsCount {
                Text("\(stash.items.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
