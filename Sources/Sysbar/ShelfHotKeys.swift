import AppKit
import Carbon.HIToolbox
import SysbarCore

/// Global shortcuts for the shelf. Carbon hot keys need no permission and fire in any app.
@MainActor
final class ShelfHotKeys {
    static let newShelf: UInt32 = 1
    static let newShelfFromClipboard: UInt32 = 2

    private static weak var current: ShelfHotKeys?

    private let onTrigger: (UInt32) -> Void
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var applied: [UInt32: KeyShortcut] = [:]

    init(onTrigger: @escaping (UInt32) -> Void) {
        self.onTrigger = onTrigger
        Self.current = self
    }

    /// Registers exactly these shortcuts, replacing the earlier ones. Nothing happens when they are unchanged.
    func apply(_ shortcuts: [UInt32: KeyShortcut]) {
        guard shortcuts != applied else { return }
        applied = shortcuts
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        guard !shortcuts.isEmpty else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let number = id.id
                DispatchQueue.main.async { MainActor.assumeIsolated { ShelfHotKeys.current?.onTrigger(number) } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        for (number, shortcut) in shortcuts {
            var ref: EventHotKeyRef?
            // A shortcut another app already owns fails here; the shelf just does not get it.
            RegisterEventHotKey(
                UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
                EventHotKeyID(signature: OSType(0x5342_5348), id: number), GetApplicationEventTarget(), 0, &ref
            )
            if let ref { registered.append(ref) }
        }
    }

    private static func carbonModifiers(_ raw: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
