import SysbarCore
import SwiftUI

/// The top bar's keep-awake button: a laptop that takes the accent colour while the Mac is kept
/// awake with its lid closed.
struct KeepAwakeButton: View {
    let isActive: Bool
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeepAwakeIcon(isKeptAwake: isActive)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(isOpen ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(KeepAwakeController.title)
        .accessibilityLabel(KeepAwakeController.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if KeepAwakeController.hasLid { return isActive ? L("Lid closed, Mac awake") : L("Lid open, Mac may sleep") }
        return isActive ? L("Mac kept awake") : L("Mac may sleep")
    }
}

/// Opens under the top bar: for how long, or while which app is open, to keep the Mac awake with
/// its lid closed.
struct KeepAwakePanel: View {
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var helper: HelperConnection
    /// Whether the list of open apps is shown, and the apps in it as of when it was opened.
    @State private var choosingApp = false
    @State private var openApps: [KeepAwakeController.WatchedApp] = []
    /// Whether the time of day is being picked, and the time shown in the picker.
    @State private var choosingTime = false
    @State private var untilTime = KeepAwakePanel.defaultUntilTime

    private enum Choice: Hashable {
        case off
        case duration(KeepAwakeDuration)
        case untilTime
        case whileCharging
        case app
    }

    /// Where the time picker starts: 8 in the morning, when a night's keeping awake would usually end.
    private static var defaultUntilTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(KeepAwakeController.title).font(.callout.weight(.medium)).help(explanation)
            dropdown
                .disabled(KeepAwakeController.hasLid && helper.state != .ready)
            if choosingTime { timeChooser }
            if choosingApp { appList }
            Toggle(L("Move the mouse when idle"), isOn: $keepAwake.movesMouse)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .help(L("While you are away, the cursor moves a little about once a minute, so apps see you as active."))
            if keepAwake.movesMouse, !keepAwake.hasMouseAccess {
                HelperNote(text: L("Moving the mouse needs Sysbar to be allowed in System Settings → Privacy & Security → Accessibility.")) {
                    Button(L("Open System Settings")) { keepAwake.openMouseAccessSettings() }
                }
            }
            status
            // Only the lid needs the helper.
            if KeepAwakeController.hasLid { helperState }
            if let error = keepAwake.lastError ?? (KeepAwakeController.hasLid ? helper.setupError : nil) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(LoadLevel.high.color)
                    Spacer(minLength: 0)
                    if helper.isUnresponsive {
                        Button(L("Set up again")) { Task { await helper.reinstall() } }.controlSize(.small)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .onAppear { keepAwake.refreshMouseAccess() }
    }

    private var explanation: String {
        KeepAwakeController.hasLid
            ? L("The Mac stays awake even when the lid is closed, so it can get warm in a bag. It sleeps again when Sysbar quits.")
            : L("The Mac does not go to sleep while this is on. It sleeps again when Sysbar quits.")
    }

    private var options: [(title: String, value: Choice)] {
        let charging: [(title: String, value: Choice)] = KeepAwakeController.hasLid ? [(L("While charging"), .whileCharging)] : []
        return [
            (L("Off"), .off),
            (L("1 hour"), .duration(.oneHour)),
            (L("4 hours"), .duration(.fourHours)),
            (L("Until a time…"), .untilTime),
            (L("Until off"), .duration(.untilOff)),
        ] + charging + [(L("While an app is open"), .app)]
    }

    /// Nil, with no option chosen, while it was turned on outside Sysbar.
    private var selection: Choice? {
        if choosingApp { return .app }
        if choosingTime { return .untilTime }
        switch keepAwake.state {
        case .off: return .off
        case .on(.duration(let duration), _): return .duration(duration)
        case .on(.until, _): return .untilTime
        case .on(.whileCharging, _): return .whileCharging
        case .on(.app, _): return .app
        case .outside: return nil
        }
    }

    /// The pop-up menu: shows the chosen option, and lists them all with a tick on the chosen one.
    private var dropdown: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    choose(option.value)
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "–").font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(KeepAwakeController.title)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .off:
            closeChoosers()
            keepAwake.stop()
        case .duration(let duration):
            closeChoosers()
            keepAwake.start(.duration(duration))
        case .whileCharging:
            closeChoosers()
            keepAwake.start(.whileCharging)
        case .untilTime:
            choosingApp = false
            choosingTime = true
        case .app:
            openApps = KeepAwakeController.openApps()
            choosingTime = false
            choosingApp = true
        }
    }

    private func closeChoosers() {
        choosingApp = false
        choosingTime = false
    }

    // MARK: Time

    private var timeChooser: some View {
        HStack(spacing: 8) {
            DatePicker(L("Until a time…"), selection: $untilTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            Spacer(minLength: 0)
            Button(L("Start"), action: startUntilTime).controlSize(.small)
        }
    }

    /// Ends at the next time the clock shows the chosen hour and minute: today, or tomorrow if it has passed.
    private func startUntilTime() {
        let time = Calendar.current.dateComponents([.hour, .minute], from: untilTime)
        let end = KeepAwakeSchedule.nextOccurrence(hour: time.hour ?? 0, minute: time.minute ?? 0, after: Date())
        closeChoosers()
        keepAwake.start(.until(end))
    }

    // MARK: Apps

    private var appList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Choose an app")).font(.caption).foregroundStyle(.secondary)
            if openApps.isEmpty {
                Text(L("No other apps are open.")).font(.caption).foregroundStyle(.secondary)
            } else {
                // A fixed height: the popover sizes itself to its content, and a scroll view alone would collapse.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(openApps, id: \.bundleID) { app in appRow(app) }
                    }
                }
                .frame(height: min(CGFloat(openApps.count) * Self.appRowHeight, Self.appListMaxHeight))
            }
        }
    }

    private func appRow(_ app: KeepAwakeController.WatchedApp) -> some View {
        Button {
            closeChoosers()
            keepAwake.start(.app(app))
        } label: {
            HStack(spacing: 6) {
                AppIcon(bundleID: app.bundleID)
                Text(app.name).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: Self.appRowHeight)
            .contentShape(Rectangle())
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }

    private static let appRowHeight: CGFloat = 24
    private static let appListMaxHeight: CGFloat = 144

    // MARK: State

    @ViewBuilder
    private var status: some View {
        switch keepAwake.state {
        case .off:
            if let reason = keepAwake.stopReason { note(text(for: reason)) }
        case .on(let plan, let endsAt):
            if let endsAt {
                HStack(spacing: 4) {
                    Text(L("Turns off in"))
                    Text(endsAt, style: .timer).monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if case .app(let app) = plan, !choosingApp {
                HStack(spacing: 6) {
                    AppIcon(bundleID: app.bundleID)
                    note(L("While %@ is open", app.name))
                }
            }
        case .outside:
            note(L("Turned on outside Sysbar."))
        }
    }

    private func text(for reason: KeepAwakeStop) -> String {
        switch reason {
        case .timeUp: L("Turned off: the time was up.")
        case .lowBattery: L("Turned off: the battery was low.")
        case .appQuit: L("Turned off: the app was closed.")
        case .unplugged: L("Turned off: the charger was unplugged.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var helperState: some View {
        switch helper.state {
        case .ready:
            EmptyView()
        case .needsApproval:
            HelperNote(text: L("Allow Sysbar's helper in System Settings → General → Login Items to keep the Mac awake.")) {
                Button(L("Open System Settings")) { helper.openApprovalSettings() }
            }
        case .notInstalled:
            HelperNote(text: L("Keeping the Mac awake needs a small helper, set up once with your administrator approval.")) {
                Button(L("Set up…")) { helper.install() }
            }
        case .unavailable:
            HelperNote(text: L("Keeping the Mac awake needs a signed copy of Sysbar.")) { EmptyView() }
        }
    }
}

/// An app's icon, found by its bundle identifier.
private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
    }

    private var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
