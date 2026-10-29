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
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences, updater: updater, helper: helper)
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
    private var preferencesSubscription: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?
    /// Animates the popover's values and graphs between samples. The menu bar is not animated:
    /// it is drawn once per sample, which keeps it cheap.
    private lazy var animator = SampleAnimator { [weak self] frame in self?.viewModel?.live.snapshot = frame }
    /// Ends remote monitoring once the device's keep-monitoring time after closing is up.
    private var remoteStopTask: Task<Void, Never>?
    /// The tab shown last, so the popover reopens where the user left it.
    private var lastSelection: DeviceSelection = .thisMac

    override init() {
        history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        let helper = HelperConnection()
        self.helper = helper
        fans = FanController(helper: helper)
        keepAwake = KeepAwakeController(helper: helper)
        super.init()
        configureButton()

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

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.remoteMonitor.closeConnections()
                self?.keepAwake.appWillTerminate()
            }
        }

        updater.start()
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
        ThermalAssessment.assess(history.items).flatMap { $0.needsAttention ? $0 : nil }
    }

    private func receive(_ snapshot: Snapshot) {
        history = history.appending(snapshot)
        lastSnapshot = snapshot
        keepAwake.evaluate(battery: snapshot.battery)
        viewModel?.history = history
        refreshMenuBar(snapshot)
        updateDescription(snapshot)
        // Only the open popover animates; with it closed, or with Reduce Motion on, the reading is
        // taken over at once, so VoiceOver also hears one value per sample.
        let animates = viewModel != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animator.push(snapshot, over: service?.interval ?? preferences.samplingInterval, animated: animates)
    }

    /// Tooltip and VoiceOver text describe the newest sample; they change once per sample, not
    /// once per animation frame.
    private func updateDescription(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        let readouts = Format.statusTitle(
            snapshot, metrics: preferences.menuBarMetrics, batteryThreshold: preferences.batteryMenuBarThreshold
        )
        let heat = heatAlert.map { "\($0.cause.title) · \($0.source.title) \(preferences.temperatureUnit.format(celsius: $0.celsius))" }
        let description = [readouts, heat].compactMap { $0 }.joined(separator: " · ")
        guard description != button.toolTip else { return }
        button.toolTip = description
        // The name stays "Sysbar"; the readings are its value, so VoiceOver says both.
        button.setAccessibilityValue(description)
    }

    private func preferencesDidChange() {
        if let service, service.interval != preferences.samplingInterval {
            service.restart(interval: preferences.samplingInterval)
            history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        }
        // A hidden button leaves no way to see or end what it started, so that ends with it.
        if !preferences.showsFanButton, fans.mode.isManual { fans.setAutomatic() }
        if !preferences.showsKeepAwakeButton, case .on = keepAwake.state { keepAwake.stop() }
        lastSignature = nil
        if let lastSnapshot {
            refreshMenuBar(lastSnapshot)
            updateDescription(lastSnapshot)
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
        draw(readouts)

        // Small touches, each a short burst of frames after a change and nothing in between.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if alert != nil, alert != previousAlert {
            // The heat warning pulses a few times when it appears or changes.
            menuBarFrames.run(duration: Self.pulseSeconds) { progress in
                draw(readouts, alertOpacity: 0.65 + 0.35 * cos(2 * .pi * Self.pulseCount * progress))
            }
        } else if !previous.isEmpty, MenuBarReadouts.blend(from: previous, to: readouts, fraction: 0.5) != readouts {
            // The bars glide to their new level instead of jumping.
            menuBarFrames.run(duration: Self.glideSeconds) { progress in
                let eased = 1 - pow(1 - progress, 3)
                draw(MenuBarReadouts.blend(from: previous, to: readouts, fraction: eased))
            }
        }
    }

    private static let glideSeconds = 0.3
    private static let pulseSeconds = 1.8
    private static let pulseCount = 3.0

    private func openSettings(page: SettingsPage?) {
        popover?.performClose(nil)
        settingsWindow.show(page: page)
    }

    /// Opens Activity Monitor (or Battery settings) for the clicked card.
    private func openDetails(for metric: MenuBarMetric) {
        popover?.performClose(nil)
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

    /// For checking the layout: `Sysbar --thermal-panel-test` opens the popover, shows and hides
    /// the thermal panel twice, and prints the popover window's top edge and height each time.
    func toggleThermalPanelForTesting() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            openPopoverForTesting()
            for step in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if let frame = popover?.contentViewController?.view.window?.frame {
                    print("step \(step) panel \(viewModel?.showsThermal == true ? "open" : "closed"): top \(Int(frame.maxY)) height \(Int(frame.height))")
                }
                viewModel?.showsThermal.toggle()
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
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        popover?.performClose(nil)
        guard let button = statusItem.button else { return }
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
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

        // The user may have just approved the helper in System Settings.
        helper.refreshState()
        keepAwake.refreshFromSystem()
        let model = PopoverViewModel(history: history)
        model.live.snapshot = lastSnapshot
        // Reopen on the tab shown last; a device that has since been deleted falls back to this Mac.
        if case .remote(let id) = lastSelection, preferences.device(id: id) == nil { lastSelection = .thisMac }
        model.selection = lastSelection
        // Opened because of the heat warning: show the fan panel straight away.
        model.showsThermal = heatAlert != nil && lastSelection == .thisMac && preferences.showsFanButton
        viewModel = model
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                preferences: preferences,
                remote: remoteMonitor,
                updater: updater,
                fans: fans,
                keepAwake: keepAwake,
                helper: helper,
                onSelect: { [weak self] in self?.select($0) },
                onRetry: { [weak self] in self?.retryRemote() },
                onSettings: { [weak self] in self?.openSettings(page: $0) },
                onOpenDetails: { [weak self] in self?.openDetails(for: $0) }
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // After the opening animation, size changes (the thermal panel) apply in one step: an
        // animated resize keeps the content centred while it runs, so the top bar would jump.
        popover.animates = false
        popover.contentViewController?.view.window?.makeKey()
        // Global monitors see only events meant for other apps, so clicks in the popover are not seen.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover?.performClose(nil) }
        }
        // Starts this Mac's apps table, or resumes (or reconnects to) the remote device shown last.
        select(lastSelection)
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        processMonitor?.stop()
        keepRemoteMonitoringAfterClose()
        viewModel = nil
        popover?.contentViewController = nil
        popover = nil
    }
}
