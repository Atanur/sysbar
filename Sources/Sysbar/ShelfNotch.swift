import AppKit
import SysbarCore

/// A drop zone over the notch, present only while files are being dragged. Files dropped on it
/// are handed to `onDrop`. Macs without a notch have none.
@MainActor
final class ShelfNotch {
    static var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } }

    var onDrop: ([URL]) -> Void = { _ in }
    private var panel: NotchPanel?
    private let view = NotchDropView()
    /// A newer drag cancels the pending hide of the last one.
    private var hideToken = 0

    func dragBegan(style: ShelfNotchStyle) {
        hideToken += 1
        guard let screen = Self.screen else { return }
        let panel = self.panel ?? makePanel()
        view.style = style
        panel.setFrame(Self.frame(on: screen), display: false)
        panel.orderFrontRegardless()
    }

    /// Hides a moment later: the drop and the mouse-up can arrive in either order.
    func dragEnded() {
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, token == hideToken else { return }
            panel?.orderOut(nil)
        }
    }

    func remove() {
        hideToken += 1
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        view.onDrop = { [weak self] urls in self?.onDrop(urls) }
        panel.contentView = view
        self.panel = panel
        return panel
    }

    /// The notch and a little room either side, from the top of the screen down to the menu bar's bottom edge.
    private static func frame(on screen: NSScreen) -> NSRect {
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notch = max(120, screen.frame.width - left - right)
        let width = notch + 120
        let height = screen.safeAreaInsets.top + 6
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    /// Sits over the menu bar, where AppKit would otherwise push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private final class NotchDropView: NSView {
    var onDrop: ([URL]) -> Void = { _ in }
    var style: ShelfNotchStyle = .hover { didSet { needsDisplay = true } }
    private var targeted = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, ShelfPasteboard.filenames])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Nearly invisible, but not clear: a window only receives a drop where something is drawn.
        NSColor(white: 0, alpha: 0.01).setFill()
        bounds.fill()
        guard targeted || style == .always else { return }
        let zone = bounds.insetBy(dx: 8, dy: 0)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: zone.minX, y: zone.maxY))
        path.line(to: NSPoint(x: zone.minX, y: zone.minY + 14))
        path.appendArc(withCenter: NSPoint(x: zone.minX + 14, y: zone.minY + 14), radius: 14, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: zone.maxX - 14, y: zone.minY))
        path.appendArc(withCenter: NSPoint(x: zone.maxX - 14, y: zone.minY + 14), radius: 14, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: zone.maxX, y: zone.maxY))
        path.lineWidth = 2
        if targeted {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.white.withAlphaComponent(0.35).setStroke()
        }
        path.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = ShelfPasteboard.containsFileURLs(sender.draggingPasteboard) ? NSDragOperation.copy : []
        targeted = operation == .copy
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        let urls = ShelfPasteboard.fileURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
