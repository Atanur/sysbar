import AppKit
import Combine
import SysbarCore
import SwiftUI

/// Owns the menu bar item. The popover's SwiftUI content and this Mac's per-app sampling exist only
/// while the popover is open; a remote session may outlive it for the device's keep-monitoring time.
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let preferences = Preferences()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// Created each time it opens and released once it has closed, so its window and SwiftUI graph
    /// do not stay in memory between uses.
    private var popover: NSPopover?
    private let remoteMonitor = RemoteMonitor()
    private let updater = UpdateChecker()
    /// The one link to the privileged helper, shared by fan control and keep-awake.
    private let helper: HelperConnection
    private let fans: FanController
    private let keepAwake: KeepAwakeController
    private let shelf: ShelfController
    /// The clipboard history, a feature of its own: it needs neither the stash nor an open panel.
    private let clipboard: ClipboardController
    /// The global shortcuts of both features, registered together.
    private lazy var hotKeys = ShelfHotKeys { [weak self] id in self?.shortcutPressed(id) }
    /// Sysbar at the top of the screen, when Settings puts it there instead of in the menu bar.
    private let notch = NotchDisplays()
    private lazy var settingsWindow = SettingsWindowController(
        preferences: preferences, updater: updater, helper: helper, shelf: shelf, clipboard: clipboard
    )
    private var service: MonitorService?
    private var processMonitor: ProcessMonitor?
    private var history: BoundedHistory<Snapshot>
    /// Plays in the menu bar until the first reading is there.
    private let launchAnimation = LaunchAnimation()
    /// Drives the menu bar's short animations: bars gliding to a new level, the heat warning pulsing.
    private let menuBarFrames = FrameTimer()
    private var shownReadouts: [MenuBarReadout] = []
    private var shownAlert: LoadLevel?
    /// Nil until the menu bar has been drawn, so even an empty one is drawn once.
    private var lastSignature: String?
    private var lastSnapshot: Snapshot?
    private var viewModel: PopoverViewModel?
    /// Closes the popover on a click anywhere else: a transient popover alone stays open once a
    /// control in it has been used (a menu, a stepper), which left it stuck on screen.
    private var outsideClickMonitor: Any?
    /// The height the popover is, or is growing or shrinking to, and the steps of that change.
    private var popoverHeight: CGFloat = 0
    private var popoverResize: Timer?
    private var preferencesSubscription: AnyCancellable?
    /// Redraws the island's feature icons when what they show changes between two samples.
    private var featureSubscription: AnyCancellable?
    /// Marks the open panel's tab on the island's icons.
    private var sectionSubscription: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    /// Animates the popover's values and graphs between samples. The menu bar is not animated:
    /// it is drawn once per sample, which keeps it cheap.
    private lazy var animator = SampleAnimator { [weak self] frame in self?.viewModel?.live.snapshot = frame }
    /// Ends remote monitoring once the device's keep-monitoring time after closing is up.
    private var remoteStopTask: Task<Void, Never>?
    /// The tab shown last, so the popover reopens where the user left it.
    private var lastSelection: DeviceSelection = .thisMac
    /// The tab the panel showed when it last closed: System, Stash or Clipboard.
    private var lastSection: PopoverSection = .system
    /// What the panel about to open is asked to show, by `showSection`; read once, when it is made.
    private var pendingTarget: PanelTarget?

    override init() {
        history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        let helper = HelperConnection()
        self.helper = helper
        fans = FanController(helper: helper)
        keepAwake = KeepAwakeController(helper: helper)
        shelf = ShelfController(preferences: preferences)
        clipboard = ClipboardController(preferences: preferences)
        super.init()
        clipboard.onAddToShelf = { [weak self] items, id in self?.shelf.add(items, to: id) }
        // The stash may be off, and then a copy has nowhere to go.
        clipboard.stashChoices = { [weak self] in
            guard let self, preferences.shelfEnabled else { return [] }
            return shelf.stashes
        }
        keepAwake.mouseWait = { [weak self] in self?.preferences.keepAwakeMouseIdle ?? MouseWander.idleSecondsBeforeMoving }
        configureButton()
        notch.makeContent = { [weak self] row, target in
            self?.makePanelContent(sizesToFit: true, row: row, target: target) ?? NSViewController()
        }
        notch.onClose = { [weak self] in self?.panelDidClose() }
        notch.onMenu = { [weak self] view, point in self?.showMenu(in: view, at: point) }
        notch.stashes = { [weak self] in self?.shelf.stashes ?? [] }
        notch.onDrop = { [weak self] urls, target in self?.shelf.drop(urls, on: target) }
        notch.features.onSelect = { [weak self] in self?.featureClicked($0) }
        notch.features.onStatus = { [weak self] in self?.statusClicked($0) }
        shelf.onReveal = { [weak self] in self?.showStashTab() }
        shelf.onSummon = { [weak self] in self?.summonStashes() }
        shelf.onFileDragBegan = { [weak self] in self?.notch.setDragHint(true) }
        shelf.onFileDragEnded = { [weak self] in self?.notch.dragEnded() }
        applyPlacement()

        processMonitor = ProcessMonitor { [weak self] usage in
            MainActor.assumeIsolated { self?.viewModel?.apps = usage }
        }
        let service = MonitorService(interval: preferences.samplingInterval) { [weak self] snapshot in
            MainActor.assumeIsolated { self?.receive(snapshot) }
        }
        self.service = service
        service.start()

        // `objectWillChange` fires before the new value is stored, so react on the next turn.
        preferencesSubscription = preferences.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.preferencesDidChange() } }
        }

        featureSubscription = Publishers.MergeMany(
            fans.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            keepAwake.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            shelf.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ).sink { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshNotchFeatures() } }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.remoteMonitor.closeConnections()
                self?.keepAwake.appWillTerminate()
                self?.shelf.appWillTerminate()
                self?.clipboard.stop()
            }
        }

        updater.start()
        syncFeatures()
        // A setting an earlier run left behind is turned off, or shown if someone else set it.
        keepAwake.refreshFromSystem()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.helper.askForApprovalIfNeeded()
        }

        if !preferences.setupCompleted {
            settingsWindow.show()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // No text: the logo, then the readings. The name is for VoiceOver and the tooltip.
        button.setAccessibilityLabel("Sysbar")
        button.toolTip = "Sysbar"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        launchAnimation.start(on: button)
    }

    /// The heat assessment when it needs attention; the menu bar then shows a warning that leads
    /// to the fan panel.
    private var heatAlert: ThermalAssessment? {
        ThermalAssessment.assess(history.items).flatMap { $0.needsAttention(preferences.heatWarning) ? $0 : nil }
    }

    private func receive(_ snapshot: Snapshot) {
        history = history.appending(snapshot)
        lastSnapshot = snapshot
        keepAwake.evaluate(battery: snapshot.battery, lowBatteryPercent: preferences.keepAwakeLowBattery)
        viewModel?.history = history
        refreshMenuBar(snapshot)
        updateDescription(snapshot)
        refreshNotch(snapshot)
        // Only the open popover animates; with it closed, or with Reduce Motion on, the reading is
        // taken over at once, so VoiceOver also hears one value per sample.
        let animates = viewModel != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animator.push(snapshot, over: service?.interval ?? preferences.samplingInterval, animated: animates)
    }

    /// Tooltip and VoiceOver text describe the newest sample; they change once per sample, not
    /// once per animation frame.
    private func updateDescription(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        let description = description(of: snapshot)
        guard description != button.toolTip else { return }
        button.toolTip = description
        // The name stays "Sysbar"; the readings are its value, so VoiceOver says both.
        button.setAccessibilityValue(description)
    }

    /// The readings in words, and the heat warning when there is one.
    private func description(of snapshot: Snapshot) -> String {
        let readouts = Format.statusTitle(
            snapshot, metrics: preferences.menuBarMetrics, batteryThreshold: preferences.batteryMenuBarThreshold
        )
        return [readouts, heatText].compactMap { $0 }.joined(separator: " · ")
    }

    /// What is warming this Mac, when it needs attention.
    private var heatText: String? {
        heatAlert.map { "\($0.cause.title) · \($0.source.title) \(preferences.temperatureUnit.format(celsius: $0.celsius))" }
    }

    /// Sysbar shows in one place: its menu bar item, or the island at the top of the screen.
    private func applyPlacement() {
        let atTop = preferences.sysbarPlacement == .notch
        statusItem.isVisible = !atTop
        guard atTop else { return notch.stop() }
        popover?.performClose(nil)
        notch.configure(
            choice: preferences.notchDisplays,
            look: NotchLook(
                background: preferences.notchBackground, iconStyle: preferences.notchIconStyle, iconSize: preferences.notchIconSize
            ),
            opensOnHover: preferences.notchOpening == .hover,
            visibility: preferences.notchVisibility
        )
        guard !notch.isRunning else { return }
        notch.start()
        if let lastSnapshot { refreshNotch(lastSnapshot) }
    }

    /// The island's System item shows the menu bar's readouts the settings leave in, as many as its ear
    /// holds beside the other items; the stash and the clipboard have an icon each while they are on, and
    /// the right ear starts with a glyph for the heat warning and for keep awake while they apply. Which
    /// ear holds what, in what order, is the user's (`notchEars`).
    private func refreshNotch(_ snapshot: Snapshot) {
        guard notch.isRunning else { return }
        let readouts = MenuBarReadouts.make(
            from: snapshot, metrics: preferences.menuBarMetrics, batteryThreshold: preferences.batteryMenuBarThreshold
        )
        // Measured at the chosen size, which is the most a display gives them (a capsule may give less).
        let scale = preferences.notchIconSize.scale
        let style = preferences.menuBarStyle
        let widths = MenuBarImage.slotWidths(readouts, style: style).map { $0 * scale }
        let features = notchFeatures()
        let statuses = notchStatuses()
        let shown = NotchGeometry.earReadouts(
            readouts.map(\.slot), hidden: Set(preferences.notchLeftHidden), limit: preferences.notchLeftCount,
            widths: widths, gap: MenuBarImage.readoutGap(for: style) * scale,
            room: readoutRoom(features: features, statuses: statuses, scale: scale)
        ).map { readouts[$0] }
        notch.setDrops(enabled: preferences.shelfEnabled, opensOnDrag: preferences.shelfNotchEnabled)
        notch.update(
            left: shown.isEmpty ? nil : MenuBarImage.make(
                shown, colored: preferences.coloredMenuBar, style: style, alert: nil,
                monochrome: preferences.notchIconStyle == .monochrome
            ),
            features: features, statuses: statuses, ears: preferences.notchEars,
            description: description(of: snapshot)
        )
    }

    /// What the System item's ear leaves the readouts, with the icons that share it as they are when
    /// the island is open: every item shows then, so the readouts stay as they are when it opens. The
    /// status glyphs, which show while closed, take their room from the right ear.
    private func readoutRoom(features: [NotchFeature], statuses: [NotchStatusInfo], scale: CGFloat) -> CGFloat {
        let ears = preferences.notchEars
        let shown = ears.ears(available: Set(features.map(\.item)).union([.system]), open: true)
        let side = NotchGeometry.featureIconSide(scale: scale)
        let onLeft = ears.ear(of: .system) == .left
        let sharing = (onLeft ? shown.left : shown.right).map {
            NotchEarEntry(item: $0, width: $0 == .system ? 0 : side, isBars: $0 == .system)
        }
        return NotchGeometry.readoutRoom(onLeft ? sharing : NotchGeometry.withStatuses(statuses.map(\.status), side: side, before: sharing))
    }

    private func refreshNotchFeatures() {
        if let lastSnapshot { refreshNotch(lastSnapshot) }
    }

    /// One icon per tab on offer besides System: the stash once it is on, and the clipboard once its
    /// history is on.
    private func notchFeatures() -> [NotchFeature] {
        var features: [NotchFeature] = []
        if preferences.shelfEnabled {
            let items = shelf.totalItemCount
            features.append(NotchFeature(section: .stash, kind: .stash(items: items), value: items > 0 ? L("%@ items", "\(items)") : ""))
        }
        if preferences.clipboardHistoryEnabled {
            features.append(NotchFeature(section: .clipboard, kind: .clipboard, value: ""))
        }
        return features
    }

    /// The signals the closed island shows: the heat warning, which the fan button of the System page
    /// explains, fans set by hand, and keep awake while it is on. Each only while its button is on offer.
    private func notchStatuses() -> [NotchStatusInfo] {
        var statuses: [NotchStatusInfo] = []
        if preferences.showsFanButton, let alert = heatAlert {
            statuses.append(NotchStatusInfo(
                status: .heat, heat: alert.level, title: L("Heat warning"), value: heatText ?? ""
            ))
        }
        if preferences.showsFanButton, fans.mode.isManual {
            statuses.append(NotchStatusInfo(status: .manualFans, title: L("Fans"), value: FanState.manual.accessibilityText))
        }
        if preferences.showsKeepAwakeButton, keepAwake.isActive {
            let value = KeepAwakeController.hasLid ? L("Lid closed, Mac awake") : L("Mac kept awake")
            statuses.append(NotchStatusInfo(status: .keepAwake, title: KeepAwakeController.title, value: value))
        }
        return statuses
    }

    /// Starts or stops the stash and the clipboard history to match Settings, and registers their shortcuts.
    private func syncFeatures() {
        shelf.sync()
        clipboard.sync()
        var shortcuts: [UInt32: KeyShortcut] = [:]
        if preferences.shelfEnabled {
            shortcuts[ShelfHotKeys.newShelf] = preferences.shelfShortcuts["new"]
            shortcuts[ShelfHotKeys.newShelfFromClipboard] = preferences.shelfShortcuts["clipboard"]
        }
        if preferences.clipboardHistoryEnabled {
            shortcuts[ShelfHotKeys.clipboardHistory] = preferences.clipboardShortcut
        }
        hotKeys.apply(shortcuts.compactMapValues { $0 })
    }

    private func shortcutPressed(_ id: UInt32) {
        switch id {
        case ShelfHotKeys.newShelf: shelf.createStash(startRenaming: true, reveal: true)
        case ShelfHotKeys.clipboardHistory: clipboard.showPanel()
        default: shelf.addClipboard()
        }
    }

    private func preferencesDidChange() {
        if let service, service.interval != preferences.samplingInterval {
            service.restart(interval: preferences.samplingInterval)
            history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        }
        // A hidden button leaves no way to see or end what it started, so that ends with it.
        if !preferences.showsFanButton, fans.mode.isManual { fans.setAutomatic() }
        if !preferences.showsKeepAwakeButton, case .on = keepAwake.state { keepAwake.stop() }
        syncFeatures()
        applyPlacement()
        lastSignature = nil
        if let lastSnapshot {
            refreshMenuBar(lastSnapshot)
            updateDescription(lastSnapshot)
            refreshNotch(lastSnapshot)
        }
    }

    /// Redraws the status item only when something visible changed.
    private func refreshMenuBar(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        // The first reading waits for the start-up animation to have played; it then draws it.
        if launchAnimation.isPlaying {
            launchAnimation.finish { [weak self] in
                guard let self, let latest = self.lastSnapshot else { return }
                self.lastSignature = nil
                self.refreshMenuBar(latest)
            }
            return
        }
        let metrics = preferences.menuBarMetrics
        let colored = preferences.coloredMenuBar
        let readouts = MenuBarReadouts.make(
            from: snapshot, metrics: metrics, batteryThreshold: preferences.batteryMenuBarThreshold
        )
        let alert = heatAlert?.level
        let style = preferences.menuBarStyle
        let signature = MenuBarImage.signature(for: readouts, colored: colored, style: style, alert: alert)
        guard signature != lastSignature else { return }
        lastSignature = signature
        let previous = shownReadouts
        let previousAlert = shownAlert
        shownReadouts = readouts
        shownAlert = alert

        func draw(_ readouts: [MenuBarReadout], alertOpacity: CGFloat = 1) {
            // With nothing to show, the logo stands in for it.
            button.image = readouts.isEmpty
                ? MenuBarLogo.image()
                : MenuBarImage.make(readouts, colored: colored, style: style, alert: alert, alertOpacity: alertOpacity)
        }
        menuBarFrames.cancel()

        // Small touches, each a short burst of frames after a change and nothing in between.
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animates, alert != nil, alert != previousAlert {
            // The heat warning pulses a few times when it appears or changes.
            draw(readouts)
            menuBarFrames.run(duration: Self.pulseSeconds) { progress in
                draw(readouts, alertOpacity: 0.65 + 0.35 * cos(2 * .pi * Self.pulseCount * progress))
            }
        } else if animates, style.showsBars, !previous.isEmpty,
                  MenuBarReadouts.blend(from: previous, to: readouts, fraction: 0.5) != readouts {
            // The bars glide to their new level instead of jumping. A frame is drawn only when a bar
            // has moved by a point: every new image makes macOS copy the item to each menu bar, which
            // costs far more than the drawing, so frames that would look the same are skipped.
            var drawn: String?
            menuBarFrames.run(duration: Self.glideSeconds) { progress in
                let eased = 1 - pow(1 - progress, 3)
                let frame = progress >= 1 ? readouts : MenuBarReadouts.blend(from: previous, to: readouts, fraction: eased)
                let frameSignature = MenuBarImage.signature(for: frame, colored: colored, style: style, alert: alert)
                guard frameSignature != drawn else { return }
                drawn = frameSignature
                draw(frame)
            }
        } else {
            draw(readouts)
        }
    }

    private static let glideSeconds = 0.3
    private static let pulseSeconds = 1.8
    private static let pulseCount = 3.0

    private func openSettings(page: SettingsPage?) {
        closePanel()
        settingsWindow.show(page: page)
    }

    /// Opens Activity Monitor (or Battery settings) for the clicked card.
    private func openDetails(for metric: MenuBarMetric) {
        closePanel()
        let hasBattery = lastSnapshot?.battery != nil
        SystemLinks.open(SystemLinks.target(for: metric, hasBattery: hasBattery))
    }

    // MARK: Device selection

    /// Switching to a remote machine starts polling it (or picks up the session already running)
    /// and pauses this Mac's per-app sampling. Switching back to this Mac leaves the remote session
    /// running, so its history is still there on the way back; it ends when another device is
    /// chosen, or when its keep-monitoring time runs out after the popover closes.
    private func select(_ selection: DeviceSelection) {
        viewModel?.selection = selection
        lastSelection = selection
        remoteStopTask?.cancel()
        switch selection {
        case .thisMac:
            startLocalProcessMonitor()
        case .remote(let id):
            processMonitor?.stop()
            guard let device = preferences.device(id: id) else { return }
            // Still being monitored from before the popover closed: keep its history going.
            if remoteMonitor.isMonitoring(device.id) { return }
            remoteMonitor.start(device, interval: device.interval)
        }
    }

    /// After the popover closes, a remote device keeps being sampled for as long as it is set to,
    /// so its graphs cover that time when the popover opens again.
    private func keepRemoteMonitoringAfterClose() {
        remoteStopTask?.cancel()
        guard
            let id = remoteMonitor.deviceID,
            let device = preferences.device(id: id),
            let seconds = device.keepMonitoring.seconds
        else { return }
        guard seconds > 0 else {
            remoteMonitor.stop()
            return
        }
        remoteStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.remoteMonitor.stop()
        }
    }

    private func retryRemote() {
        guard case .remote(let id) = viewModel?.selection, let device = preferences.device(id: id) else { return }
        remoteMonitor.start(device, interval: device.interval)
    }

    private func startLocalProcessMonitor() {
        if preferences.showsApps {
            processMonitor?.start(
                interval: SamplingInterval.processInterval(for: preferences.samplingInterval),
                readsNetwork: preferences.isColumnVisible(.network)
            )
        }
    }

    // MARK: Popover

    /// For measuring: `Sysbar --open-popover` opens the popover right after launch.
    /// It stays open until Sysbar quits, whatever is clicked, so its cost can be measured from outside.
    func openPopoverForTesting() {
        if popover?.isShown != true { togglePopover() }
        popover?.behavior = .applicationDefined
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// For measuring memory: `Sysbar --popover-cycles N` opens and closes the popover N times and
    /// prints the footprint after each close, then quits.
    func cyclePopoverForTesting(times: Int) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            print("start: \(Self.footprintMegabytes()) MB")
            for cycle in 1...max(times, 1) {
                togglePopover()
                try? await Task.sleep(for: .seconds(3))
                popover?.performClose(nil)
                try? await Task.sleep(for: .seconds(2))
                print("after close \(cycle): \(Self.footprintMegabytes()) MB")
            }
            NSApp.terminate(nil)
        }
    }

    /// For measuring memory: `Sysbar --settings-cycles N` opens the settings window N times, shows
    /// every page, closes it, and prints the footprint after each close, then quits.
    func cycleSettingsForTesting(times: Int) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            print("start: \(Self.footprintMegabytes()) MB")
            for cycle in 1...max(times, 1) {
                for page in SettingsPage.all(deviceIDs: preferences.devices.map(\.id)) {
                    settingsWindow.show(page: page)
                    try? await Task.sleep(for: .milliseconds(700))
                }
                settingsWindow.closeForTesting()
                try? await Task.sleep(for: .seconds(2))
                print("after close \(cycle): \(Self.footprintMegabytes()) MB")
            }
            NSApp.terminate(nil)
        }
    }

    /// For checking the layout: `Sysbar --thermal-panel-test` opens the popover, unfolds and folds
    /// the fan panel twice, and prints the popover window's top edge and height each time.
    func toggleThermalPanelForTesting() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            openPopoverForTesting()
            for step in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if let frame = popover?.contentViewController?.view.window?.frame {
                    print("step \(step) panel \(viewModel?.panel == .thermal ? "fans" : "none"): top \(Int(frame.maxY)) height \(Int(frame.height))")
                }
                viewModel?.panel = viewModel?.panel == .thermal ? nil : .thermal
            }
            NSApp.terminate(nil)
        }
    }

    /// For checking fan control end to end: `Sysbar --fan-test` sets the fans to manual 60%,
    /// prints what the SMC reports, hands them back to automatic, prints again, and quits.
    func fanTest() {
        Task {
            @MainActor func report(_ label: String) {
                let keys = ["F0Md", "F1Md", "F0Tg", "F1Tg", "F0Ac", "F1Ac"]
                let values = keys.map { key in
                    SystemPower.rawValue(key).map { value -> String in
                        value.type == "flt " && value.bytes.count == 4
                            ? "\(key)=\(Int(value.bytes.withUnsafeBytes { $0.load(as: Float.self) }))"
                            : "\(key)=\(value.bytes.first.map(String.init) ?? "?")"
                    } ?? "\(key)=?"
                }
                print(label, values.joined(separator: " "), "| state \(helper.state) mode \(fans.mode) error \(fans.lastError ?? "none")")
            }
            try? await Task.sleep(for: .seconds(2))
            report("before:")
            fans.setManual(0.6)
            try? await Task.sleep(for: .seconds(6))
            report("manual 60%:")
            fans.setAutomatic()
            try? await Task.sleep(for: .seconds(3))
            report("automatic:")
            NSApp.terminate(nil)
        }
    }

    private static func footprintMegabytes() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return "?" }
        return String(format: "%.1f", Double(info.phys_footprint) / 1_048_576)
    }

    /// For testing the updater: `Sysbar --update-now` checks at once and installs what it finds,
    /// as pressing Update would.
    func updateNowForTesting() {
        Task {
            await updater.check(userInitiated: true)
            print("update check:", updater.state)
            if let release = updater.offered { await updater.install(release) }
            print("update result:", updater.state)
        }
    }

    /// A click opens the popover; a right click, or a click with Control held, opens a small menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let button = statusItem.button else { return }
            showMenu(in: button, at: NSPoint(x: 0, y: button.bounds.height + 5))
        } else {
            togglePopover()
        }
    }

    private func showMenu(in view: NSView, at point: NSPoint) {
        closePanel()
        let menu = NSMenu()
        for (title, key, action) in [
            (L("Settings"), ",", #selector(openSettingsFromMenu)),
            (L("Check for updates"), "", #selector(checkForUpdatesFromMenu)),
            (L("About"), "", #selector(openAboutFromMenu)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Quit Sysbar"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func openSettingsFromMenu() { openSettings(page: nil) }

    @objc private func openAboutFromMenu() { openSettings(page: .about) }

    /// The About page shows what the check finds.
    @objc private func checkForUpdatesFromMenu() {
        openSettings(page: .about)
        Task { await updater.check(userInitiated: true) }
    }

    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover
        let controller = makePanelContent(sizesToFit: false)
        // The popover is sized here, from the page's height, not by the content: left to it, the popover
        // jumps to each page's height, and is first placed for the default 320 × 320 and then grows
        // upwards, off the top of the screen.
        controller.sizingOptions = [.intrinsicContentSize]
        popover.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = popoverSize(forContentHeight: controller.view.fittingSize.height, below: button)
        popoverHeight = popover.contentSize.height
        // From here on the page reports its height (`PopoverView.onHeight`) and the popover follows it
        // with `resizePopover`; the content is anchored to its top (see `PopoverView.body`), so the top
        // bar stays still while the bottom moves.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Global monitors see only events meant for other apps, so clicks in the popover are not seen.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover?.performClose(nil) }
        }
    }

    /// What the popover keeps from the room below the menu bar item: its arrow, its inset and the
    /// screen's edge.
    private static let popoverEdgeMargin: CGFloat = 40

    /// How long the popover takes to follow a page's new height.
    private static let popoverResizeDuration: TimeInterval = 0.25

    /// The size for a page that wants `height`, within the room below the menu bar item.
    private func popoverSize(forContentHeight height: CGFloat, below button: NSStatusBarButton) -> NSSize {
        let window = button.window
        let room = (window?.frame.minY ?? 0) - ((window?.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0) - Self.popoverEdgeMargin
        return NSSize(width: PopoverView.width, height: PageHeight.popoverHeight(wanted: height, room: room))
    }

    /// Follows the page's height as another tab is shown or a panel unfolds.
    private func fitPopover(toContentHeight height: CGFloat) {
        guard let popover, popover.isShown, let button = statusItem.button, height > 0 else { return }
        let size = popoverSize(forContentHeight: height, below: button)
        guard abs(size.height - popoverHeight) > 0.5 else { return }
        popoverHeight = size.height
        resizePopover(popover, to: size)
    }

    /// An `NSPopover` jumps to a new `contentSize`, so the steps in between are set here. The top
    /// edge stays under the menu bar item: only the bottom moves.
    private func resizePopover(_ popover: NSPopover, to size: NSSize) {
        popoverResize?.invalidate()
        popoverResize = nil
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { popover.contentSize = size; return }
        let from = popover.contentSize.height
        let start = Date()
        popoverResize = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self, weak popover] timer in
            MainActor.assumeIsolated {
                guard let popover, popover.isShown else { return timer.invalidate() }
                let progress = min(Date().timeIntervalSince(start) / Self.popoverResizeDuration, 1)
                let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
                popover.contentSize = NSSize(width: size.width, height: (from + (size.height - from) * eased).rounded())
                if progress >= 1 {
                    timer.invalidate()
                    self?.popoverResize = nil
                }
            }
        }
    }

    /// What the popover shows, for the menu bar item or the island at the top of the screen.
    /// Making it also starts what an open panel needs: this Mac's apps table, or the remote device
    /// shown last. `sizesToFit` reports its size as it changes, for the island to follow. `target` is
    /// what was asked for, by the readouts or an icon the island was opened from: a tab, and on the
    /// System page a panel unfolded.
    private func makePanelContent(sizesToFit: Bool, row: NotchRowModel? = nil, target: PanelTarget? = nil) -> PanelHostingController<PopoverView> {
        // The user may have just approved the helper in System Settings.
        helper.refreshState()
        keepAwake.refreshFromSystem()
        let model = PopoverViewModel(history: history)
        model.live.snapshot = lastSnapshot
        // Reopen on the tab shown last; a device that has since been deleted falls back to this Mac.
        if case .remote(let id) = lastSelection, preferences.device(id: id) == nil { lastSelection = .thisMac }
        model.selection = lastSelection
        // A tab asked for comes first. Opened because of the heat warning: the System page with the fan
        // panel unfolded straight away, whatever tab was shown last.
        let asked = pendingTarget ?? target
        pendingTarget = nil
        if let asked {
            model.section = asked.section
            model.panel = asked.panel
        } else if heatAlert != nil && preferences.showsFanButton {
            model.section = .system
            model.panel = .thermal
        } else {
            model.section = lastSection
        }
        viewModel = model
        sectionSubscription = sizesToFit ? model.$section.sink { [weak self] in self?.notch.features.active = $0 } : nil
        let controller = PanelHostingController(
            rootView: PopoverView(
                model: model,
                preferences: preferences,
                remote: remoteMonitor,
                updater: updater,
                fans: fans,
                keepAwake: keepAwake,
                helper: helper,
                shelf: shelf,
                clipboard: clipboard,
                topRow: row ?? NotchRowModel(),
                onSelect: { [weak self] in self?.select($0) },
                onRetry: { [weak self] in self?.retryRemote() },
                onSettings: { [weak self] in self?.openSettings(page: $0) },
                onOpenDetails: { [weak self] in self?.openDetails(for: $0) },
                onClose: { [weak self] in self?.closePanel() },
                // Only the island's panel sizes to fit, and it opens under the notch, where there is room sideways.
                isWide: sizesToFit,
                onHeight: sizesToFit ? nil : { [weak self] in self?.fitPopover(toContentHeight: $0) }
            )
        )
        if sizesToFit {
            controller.sizingOptions = [.preferredContentSize]
            // The island follows the panel's height from page to page and as panels unfold.
            controller.onHeightChange = { [weak self] in self?.notch.contentSizeChanged() }
        }
        select(lastSelection)
        return controller
    }

    /// Brings up the Stash tab, opening the panel if it is closed: for a stash that was just made and
    /// wants a name.
    private func showStashTab() {
        showSection(.stash)
        // Typing the new stash's name needs the keyboard, which an inactive menu bar app does not have.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Shows a tab, and on the System page a panel unfolded, opening the island or the popover first
    /// when it is closed, and keeping the island open.
    private func showSection(_ section: PopoverSection, panel: PopoverPanel? = nil) {
        lastSection = section
        if viewModel == nil {
            pendingTarget = PanelTarget(section: section, panel: panel)
            if preferences.sysbarPlacement == .notch { notch.open(pinned: true) } else { togglePopover() }
            pendingTarget = nil
        } else if notch.isOpen {
            notch.open(pinned: true)
        }
        viewModel?.section = section
        if let panel { viewModel?.panel = panel }
    }

    /// A click on a feature's icon in the island: its tab, or closed again when it is already the one
    /// shown and the island was opened on purpose, not by resting the pointer on it.
    private func featureClicked(_ section: PopoverSection) {
        if notch.isPinned, viewModel?.section == section { return notch.close() }
        showSection(section)
    }

    /// A click on a status glyph of the closed island: the System page with the glyph's panel unfolded.
    private func statusClicked(_ status: NotchStatus) {
        showSection(.system, panel: status.panel)
    }

    /// A shake or the modifier key during a file drag: the stashes to drop on, in the island, or on the
    /// Stash tab of the popover when Sysbar is in the menu bar. The open island goes to the tab.
    private func summonStashes() {
        guard preferences.sysbarPlacement == .notch, notch.isRunning, !notch.isOpen else { return showSection(.stash) }
        notch.showPicker(summoned: true)
    }

    /// Closes the popover or the island's panel, whichever is open.
    private func closePanel() {
        popover?.performClose(nil)
        notch.close()
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        popoverResize?.invalidate()
        popoverResize = nil
        popover?.contentViewController = nil
        popover = nil
        panelDidClose()
    }

    /// Stops what only an open panel needs.
    private func panelDidClose() {
        if let viewModel { lastSection = viewModel.section }
        sectionSubscription = nil
        notch.features.active = nil
        processMonitor?.stop()
        keepRemoteMonitoringAfterClose()
        viewModel = nil
        returnFreedMemory()
    }

    /// Hands the pages the closed panel freed back to macOS. The allocator otherwise keeps them for
    /// later, so a Mac that opened the panel a few times would show Sysbar several times its resting
    /// size. It waits for the panel's views to be torn down first.
    private func returnFreedMemory() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.memoryReleaseDelay) { [weak self] in
            guard self?.viewModel == nil else { return }
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    private static let memoryReleaseDelay: TimeInterval = 2
}
