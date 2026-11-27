import AppKit
import SwiftUI
import SysbarCore

/// The folder a feature keeps its data in: where it is now, and buttons to choose another, go back to
/// the default one and show it in Finder. Choosing is up to the caller, which moves the data.
struct StorageLocationRow: View {
    /// What is kept there, for VoiceOver ("the clipboard history").
    let noun: String
    /// The folder the data is in, and whether it is the default one.
    let directory: URL
    let isDefault: Bool
    /// False while the folder cannot be reached, such as a drive that is not connected.
    let isAvailable: Bool
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        SettingsRow(
            symbol: "folder", title: L("Folder"),
            subtitle: isAvailable
                ? StorageLocation.displayPath(directory.path)
                : StorageLocation.displayPath(directory.path) + " · " + L("Not available")
        ) {
            HStack(spacing: 8) {
                Button(L("Choose…"), action: onChoose)
                    .accessibilityLabel(L("Choose a folder for %@", noun))
                Menu {
                    Button(L("Show in Finder"), action: reveal)
                    Button(L("Reset to Default"), action: onReset).disabled(isDefault)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(L("More folder actions for %@", noun))
            }
        }
    }

    private func reveal() {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else if manager.fileExists(atPath: directory.deletingLastPathComponent().path) {
            NSWorkspace.shared.open(directory.deletingLastPathComponent())
        } else {
            NSSound.beep()
        }
    }
}

/// The folder picker and the questions that come with moving data to another folder.
@MainActor
enum StorageDialogs {
    /// A folder chosen in an open panel, or nil if the panel was cancelled.
    static func chooseFolder(startingAt directory: URL, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = message
        panel.prompt = L("Choose")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// What to do with the clipboard history when its folder changes; nil if the user cancelled.
    static func clipboardRelocation(
        currentHasHistory: Bool, destinationHasHistory: Bool
    ) -> ClipboardController.Relocation? {
        if destinationHasHistory {
            let alert = alert(
                L("That folder already holds a clipboard history"),
                L("Sysbar can use it. The history in the current folder is then deleted."),
                buttons: [L("Use That History"), L("Cancel")]
            )
            return alert == .alertFirstButtonReturn ? .useExisting : nil
        }
        guard currentHasHistory else { return .move }
        let answer = alert(
            L("Move the clipboard history?"),
            L("Move takes the history to the new folder. Start Fresh begins an empty history there and deletes the old one."),
            buttons: [L("Move"), L("Start Fresh"), L("Cancel")]
        )
        switch answer {
        case .alertFirstButtonReturn: return .move
        case .alertSecondButtonReturn: return .startFresh
        default: return nil
        }
    }

    /// Whether to use the stashes a folder already holds (true), or move these there (false); nil if cancelled.
    static func stashRelocation(destinationHasStashes: Bool) -> Bool? {
        if destinationHasStashes {
            let answer = alert(
                L("That folder already holds stashes"),
                L("Sysbar can use them instead. The stashes in the current folder are left where they are."),
                buttons: [L("Use Those Stashes"), L("Cancel")]
            )
            return answer == .alertFirstButtonReturn ? true : nil
        }
        let answer = alert(
            L("Move the stashes?"),
            L("Your stashes move to the new folder. Files in them stay where they are."),
            buttons: [L("Move"), L("Cancel")]
        )
        return answer == .alertFirstButtonReturn ? false : nil
    }

    static func showFailure(_ message: String) {
        _ = alert(L("The folder could not be changed"), message, buttons: [L("OK")], style: .warning)
    }

    private static func alert(
        _ title: String, _ detail: String, buttons: [String], style: NSAlert.Style = .informational
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}
