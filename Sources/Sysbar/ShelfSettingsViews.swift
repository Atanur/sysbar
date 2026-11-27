import AppKit
import SwiftUI
import SysbarCore
import UniformTypeIdentifiers

extension ShelfModifier {
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .command: .command
        }
    }

    var title: String {
        switch self {
        case .shift: "⇧ " + L("Shift")
        case .option: "⌥ " + L("Option")
        case .control: "⌃ " + L("Control")
        case .command: "⌘ " + L("Command")
        }
    }
}

extension DragShake.Sensitivity {
    var title: String {
        switch self {
        case .low: L("Low")
        case .standard: L("Default")
        case .high: L("High")
        }
    }
}

/// Records a global shortcut: click, then press the keys. Escape cancels; Delete clears.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    @State private var recording = false
    @State private var monitor: Any?
    @Environment(\.settingsRowTitle) private var title

    var body: some View {
        Button(recording ? L("Type shortcut…") : shortcut?.display ?? L("Record shortcut")) {
            recording ? stop() : start()
        }
        // Named after what it sets; the key combination is its value.
        .accessibilityLabel(title.isEmpty ? L("Record shortcut") : title)
        .accessibilityValue(shortcut?.display ?? "")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53: return stop()
        case 51, 117:
            shortcut = nil
            return stop()
        default: break
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = Self.name(of: event)
        // A bare letter or ⇧ plus a letter would swallow typing in every app.
        let isFunctionKey = key.hasPrefix("F") && key.count > 1
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else {
            return NSSound.beep()
        }
        shortcut = KeyShortcut(keyCode: event.keyCode, modifiers: flags.rawValue, key: key)
        stop()
    }

    private static func name(of event: NSEvent) -> String {
        let names: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}

/// The stash's global shortcuts, each recorded here. The clipboard history's is on its own page.
struct ShelfShortcutsSheet: View {
    @ObservedObject var preferences: Preferences
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Keyboard shortcuts")).font(.headline)
            Text(L("Click a shortcut, then press the keys. Press Delete to clear it."))
                .font(.callout).foregroundStyle(.secondary)
            row(L("New Stash"), key: "new")
            row(L("Add Clipboard to Stash"), key: "clipboard")
            HStack {
                Spacer()
                Button(L("Done"), action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func row(_ title: String, key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: Binding(
                get: { preferences.shelfShortcuts[key] },
                set: { preferences.shelfShortcuts[key] = $0 }
            ))
            .environment(\.settingsRowTitle, title)
        }
    }
}

/// Apps the stash or the clipboard history leaves alone, by bundle identifier.
struct IgnoredAppsSheet: View {
    @Binding var apps: [String]
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Ignored applications")).font(.headline)
            Text(message)
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(apps, id: \.self) { identifier in
                    HStack {
                        let app = Self.location(of: identifier)
                        Image(nsImage: app.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                            .resizable().frame(width: 20, height: 20)
                        Text(app.map { FileManager.default.displayName(atPath: $0.path) } ?? identifier)
                        Spacer()
                        Button(L("Remove")) { apps.removeAll { $0 == identifier } }
                    }
                }
            }
            .frame(height: 160)
            HStack {
                Button(L("Add application…"), action: add)
                Spacer()
                Button(L("Done"), action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private static func location(of identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier,
                  !apps.contains(identifier) else { continue }
            apps.append(identifier)
        }
    }
}
