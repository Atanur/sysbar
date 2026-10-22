import AppKit
import SwiftUI

/// Owns the settings window. The window and its SwiftUI content exist only while it is open, and
/// the app shows in the Dock and app switcher meanwhile so the window behaves like a normal one.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let contentSize = NSSize(width: 820, height: 580)

    private let preferences: Preferences
    private let updater: UpdateChecker
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(preferences: Preferences, updater: UpdateChecker) {
        self.preferences = preferences
        self.updater = updater
    }

    /// Shows the window, on `page` if one is given and otherwise on the page shown last.
    /// For measuring memory: closes the window as the close button would.
    func closeForTesting() {
        window?.performClose(nil)
    }

    func show(page: SettingsPage? = nil) {
        if let page { navigation.selection = page }
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SettingsView(preferences: preferences, updater: updater, navigation: navigation))
        let window = NSWindow(contentViewController: controller)
        window.title = "Sysbar"
        // Full-height sidebar with the traffic lights over it, like System Settings.
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setContentSize(Self.contentSize)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window ends the first-run welcome and returns the app to menu bar only.
    func windowWillClose(_ notification: Notification) {
        preferences.setupCompleted = true
        window?.contentViewController = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
