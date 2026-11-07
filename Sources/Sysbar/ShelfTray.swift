import AppKit
import SysbarCore

/// The shelves' menu bar icon: new shelves, recent ones, and a way to Settings.
@MainActor
final class ShelfTray: NSObject, NSMenuDelegate {
    private static let recentCount = 3

    private unowned let controller: ShelfController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(controller: ShelfController) {
        self.controller = controller
        super.init()
        let menu = NSMenu()
        // Otherwise AppKit enables every item with an action and ignores `isEnabled`.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: L("File shelf"))
        statusItem.button?.toolTip = L("File shelf")
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(L("New Shelf"), #selector(newShelf), shortcut: controller.shortcutForNewShelf))
        let clipboard = item(L("New Shelf From Clipboard"), #selector(newShelfFromClipboard), shortcut: controller.shortcutForClipboard)
        clipboard.isEnabled = controller.clipboardHasFiles
        menu.addItem(clipboard)
        if controller.openShelfCount > 0 {
            menu.addItem(item(L("Close All Shelves"), #selector(closeAllShelves)))
        }

        // A shelf whose files are all gone has nothing to bring back.
        let recent = controller.history.filter { $0.paths.contains { FileManager.default.fileExists(atPath: $0) } }
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: L("Recent Shelves")))
            recent.prefix(Self.recentCount).forEach { menu.addItem(recordItem($0)) }
            if recent.count > Self.recentCount {
                let all = NSMenuItem(title: L("All Shelves"), action: nil, keyEquivalent: "")
                all.submenu = NSMenu()
                recent.forEach { all.submenu?.addItem(recordItem($0)) }
                menu.addItem(all)
            }
            menu.addItem(item(L("Clear Recent Shelves"), #selector(clearHistory)))
        }

        menu.addItem(.separator())
        menu.addItem(item(L("Settings"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Sysbar"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", shortcut: KeyShortcut? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.menuKey ?? key)
        if let shortcut, shortcut.menuKey != nil {
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        }
        item.target = self
        return item
    }

    /// The first file's name, how many more there are, and when the shelf was put away.
    private func recordItem(_ record: ShelfRecord) -> NSMenuItem {
        let first = record.paths.first { FileManager.default.fileExists(atPath: $0) } ?? record.paths[0]
        let more = record.paths.count - 1
        let name = FileManager.default.displayName(atPath: first) + (more > 0 ? " +\(more)" : "")
        let item = self.item(name, #selector(restore(_:)))
        item.representedObject = record
        if #available(macOS 14.4, *) {
            item.subtitle = dates.string(from: record.date)
        } else {
            item.toolTip = dates.string(from: record.date)
        }
        let icon = NSWorkspace.shared.icon(forFile: first)
        icon.size = NSSize(width: 28, height: 28)
        item.image = icon
        return item
    }

    @objc private func newShelf() { controller.newShelf() }
    @objc private func newShelfFromClipboard() { controller.newShelfFromClipboard() }
    @objc private func closeAllShelves() { controller.closeAllShelves() }
    @objc private func clearHistory() { controller.clearHistory() }
    @objc private func openSettings() { controller.openShelfSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func restore(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? ShelfRecord else { return }
        controller.restore(record)
    }
}
