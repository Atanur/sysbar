import AppKit
import SysbarCore
import SwiftUI

/// "How to connect a device", folded under the device list: the commands to run on a Mac or a Linux
/// server and then on this Mac, each with a copy button. Sysbar runs none of them.
struct DeviceSetupGuideView: View {
    @State private var isOpen = false
    @State private var system = DeviceSetupGuide.System.mac

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                Divider()
                content.padding(12)
            }
        }
        .settingsCard()
        .motion(.snappy(duration: 0.2), value: isOpen)
    }

    private var header: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 10) {
                IconTile(symbol: "terminal", size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("How to connect a device"))
                    Text(L("A few commands to run once, for a Mac or a Linux server"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? L("Expanded") : L("Collapsed"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L("System"), selection: $system) {
                Text(verbatim: "Mac").tag(DeviceSetupGuide.System.mac)
                Text(verbatim: "Linux").tag(DeviceSetupGuide.System.linux)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            GuideSteps(steps: DeviceSetupGuide.steps(for: system, existingKey: Self.existingKey()))
        }
    }

    /// Looked up each time the guide is drawn, so a key made while it is open shows up.
    static func existingKey() -> String? {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh").path
        return DeviceSetupGuide.defaultKey(in: directory) { FileManager.default.fileExists(atPath: $0) }
    }
}

/// The numbered steps, here and in the sheet that adds a found device.
struct GuideSteps: View {
    let steps: [DeviceSetupGuide.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                GuideStep(number: index + 1, step: step)
            }
        }
    }
}

/// One numbered step: title, a line of explanation and its commands. A step this Mac has already
/// done is drawn fainter.
private struct GuideStep: View {
    let number: Int
    let step: DeviceSetupGuide.Step

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title).font(.callout.weight(.medium))
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(step.commands, id: \.text) { command in
                    GuideCommand(command: command)
                }
            }
        }
        .opacity(step.isOptional ? 0.6 : 1)
    }
}

/// A command in monospaced type, selectable, with a button that copies it.
private struct GuideCommand: View {
    private static let copiedFeedback = Duration.seconds(1.5)

    let command: DeviceSetupGuide.Command
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = command.label {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(command.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .help(L("Copy command"))
                .accessibilityLabel(L("Copy command"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.text, forType: .string)
        copied = true
        announce(L("Copied"))
        Task {
            try? await Task.sleep(for: Self.copiedFeedback)
            copied = false
        }
    }
}
