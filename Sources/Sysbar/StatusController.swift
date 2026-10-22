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
    private let popover = NSPopover()
    private let remoteMonitor = RemoteMonitor()
    private lazy var settingsWindow = SettingsWindowController(preferences: preferences)
    private var service: MonitorService?
    private var processMonitor: ProcessMonitor?
    private var history: BoundedHistory<Snapshot>
    private var lastSignature = ""
    private var lastSnapshot: Snapshot?
    private var viewModel: PopoverViewModel?
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
        super.init()
        configureButton()
        popover.behavior = .transient
        popover.delegate = self

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
            MainActor.assumeIsolated { self?.remoteMonitor.closeConnections() }
        }

        if !preferences.setupCompleted {
            settingsWindow.show()
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.title = "Sysbar"
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func receive(_ snapshot: Snapshot) {
        history = history.appending(snapshot)
        lastSnapshot = snapshot
        viewModel?.history = history
        refreshMenuBar(snapshot)
        updateDescription(snapshot)
        // Only the open popover animates; with it closed the reading is taken over at once.
        animator.push(snapshot, over: service?.interval ?? preferences.samplingInterval, animated: viewModel != nil)
    }

    /// Tooltip and VoiceOver text describe the newest sample; they change once per sample, not
    /// once per animation frame.
    private func updateDescription(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        let description = Format.statusTitle(snapshot, metrics: preferences.menuBarMetrics)
        guard description != button.toolTip else { return }
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func preferencesDidChange() {
        if let service, service.interval != preferences.samplingInterval {
            service.restart(interval: preferences.samplingInterval)
            history = BoundedHistory(capacity: SamplingInterval.historyPoints)
        }
        lastSignature = ""
        if let lastSnapshot {
            refreshMenuBar(lastSnapshot)
            updateDescription(lastSnapshot)
        }
    }

    /// Redraws the status item only when something visible changed.
    private func refreshMenuBar(_ snapshot: Snapshot) {
        guard let button = statusItem.button else { return }
        let metrics = preferences.menuBarMetrics
        let colored = preferences.coloredMenuBar
        let readouts = MenuBarReadouts.make(from: snapshot, metrics: metrics)
        let signature = MenuBarImage.signature(for: readouts, colored: colored)
        guard signature != lastSignature else { return }
        lastSignature = signature

        // Only the image changes from frame to frame; the rest is set when it actually differs.
        let title = readouts.isEmpty ? "Sysbar" : ""
        if button.title != title { button.title = title }
        let position: NSControl.ImagePosition = readouts.isEmpty ? .noImage : .imageOnly
        if button.imagePosition != position { button.imagePosition = position }
        button.image = readouts.isEmpty ? nil : MenuBarImage.make(readouts, colored: colored)
    }

    private func openSettings(page: SettingsPage?) {
        popover.performClose(nil)
        settingsWindow.show(page: page)
    }

    /// Opens Activity Monitor (or Battery settings) for the clicked card.
    private func openDetails(for metric: MenuBarMetric) {
        popover.performClose(nil)
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
            processMonitor?.start(interval: SamplingInterval.processInterval(for: preferences.samplingInterval))
        }
    }

    // MARK: Popover

    /// For measuring: `Sysbar --open-popover` opens the popover right after launch.
    func openPopoverForTesting() {
        if !popover.isShown { togglePopover() }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }

        let model = PopoverViewModel(history: history)
        model.live.snapshot = lastSnapshot
        // Reopen on the tab shown last; a device that has since been deleted falls back to this Mac.
        if case .remote(let id) = lastSelection, preferences.device(id: id) == nil { lastSelection = .thisMac }
        model.selection = lastSelection
        viewModel = model
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                model: model,
                preferences: preferences,
                remote: remoteMonitor,
                onSelect: { [weak self] in self?.select($0) },
                onRetry: { [weak self] in self?.retryRemote() },
                onSettings: { [weak self] in self?.openSettings(page: $0) },
                onOpenDetails: { [weak self] in self?.openDetails(for: $0) }
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Starts this Mac's apps table, or resumes (or reconnects to) the remote device shown last.
        select(lastSelection)
    }

    func popoverDidClose(_ notification: Notification) {
        processMonitor?.stop()
        keepRemoteMonitoringAfterClose()
        viewModel = nil
        popover.contentViewController = nil
    }
}
