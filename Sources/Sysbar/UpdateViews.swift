import SysbarCore
import SwiftUI

/// The popover's suggestion to update: shown only when a newer release was found and not skipped.
struct UpdateBanner: View {
    @ObservedObject var updater: UpdateChecker
    let release: ReleaseInfo
    @State private var showsNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            if showsNotes {
                ReleaseNotesList(items: release.notes)
                    .font(.caption)
                Button(L("Release notes")) { updater.openReleasePage(release) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Sysbar %@ is available", release.version.description))
                    .font(.callout.weight(.medium))
                if case .failed(let message) = updater.state {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    whatsNew
                }
            }
            Spacer(minLength: 4)
            if updater.state == .installing {
                ProgressView().controlSize(.small)
                Text(L("Installing…")).font(.caption).foregroundStyle(.secondary)
            } else {
                Button(L("Update")) { Task { await updater.install(release) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button { updater.skip(release) } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Skip this version"))
                .accessibilityLabel(L("Skip this version"))
            }
        }
    }

    /// Unfolds the release's notes in place; a release without notes opens its page instead.
    private var whatsNew: some View {
        Button {
            if release.notes.isEmpty {
                updater.openReleasePage(release)
            } else {
                showsNotes.toggle()
            }
        } label: {
            HStack(spacing: 2) {
                Text(L("What's new"))
                if !release.notes.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showsNotes ? 180 : 0))
                }
            }
        }
        .buttonStyle(.link)
        .font(.caption)
        .accessibilityValue(release.notes.isEmpty ? "" : (showsNotes ? L("Expanded") : L("Collapsed")))
        .motion(.snappy(duration: 0.2), value: showsNotes)
    }
}

/// The About page's update controls: the automatic check and a manual one with its result.
struct UpdateSettingsGroup: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        SettingsGroup(
            title: L("Updates"),
            footer: L("Sysbar only asks GitHub for its latest release. Nothing about this Mac is sent.")
        ) {
            SettingsRow(
                symbol: "arrow.triangle.2.circlepath", title: L("Check automatically"), subtitle: L("Once a day")
            ) {
                RowToggle(isOn: $updater.isAutomatic)
            }
            RowDivider()
            SettingsRow(symbol: "arrow.down.circle", title: statusTitle, subtitle: statusDetail) {
                actions
            }
        }
    }

    private var statusTitle: String {
        switch updater.state {
        case .checking: L("Checking…")
        case .upToDate: L("Sysbar is up to date")
        case .available(let release): L("Sysbar %@ is available", release.version.description)
        case .installing: L("Installing…")
        case .idle, .failed: L("Check for updates")
        }
    }

    private var statusDetail: String? {
        if case .failed(let message) = updater.state { return message }
        return nil
    }

    @ViewBuilder
    private var actions: some View {
        switch updater.state {
        case .checking, .installing:
            ProgressView().controlSize(.small)
        case .available(let release):
            Button(L("What's new")) { updater.openReleasePage(release) }
            Button(L("Update")) { Task { await updater.install(release) } }
                .buttonStyle(.borderedProminent)
        case .idle, .upToDate, .failed:
            Button(L("Check now")) { Task { await updater.check(userInitiated: true) } }
        }
    }
}
