import AppKit
import SysbarCore
import SwiftUI

/// Tells VoiceOver about a change that is only drawn, such as a finished check or a copied command,
/// so someone not looking at that spot still hears it.
@MainActor
func announce(_ message: String) {
    AccessibilityNotification.Announcement(message).post()
}

/// A transfer rate as VoiceOver should say it: "1.2 MB per second" rather than "1.2M".
func spokenRate(_ bytesPerSecond: Double) -> String {
    L("%@ per second", ByteCountFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0)), countStyle: .binary))
}

/// The menu bar menu shown while the settings window is open. It is what gives text fields the
/// usual shortcuts, ⌘C, ⌘V, ⌘A, ⌘Z, and the window ⌘W and ⌘M; without it those keys do nothing.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(title: "Sysbar", items: [
            NSMenuItem(title: L("Quit Sysbar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        main.addItem(submenu(title: L("Edit"), items: [
            NSMenuItem(title: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z"),
            shifted(NSMenuItem(title: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")),
            .separator(),
            NSMenuItem(title: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        main.addItem(submenu(title: L("Window"), items: [
            NSMenuItem(title: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        return main
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    private static func shifted(_ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
