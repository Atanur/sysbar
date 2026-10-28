import SysbarCore
import SwiftUI

/// Whether a remote device answered the last time its settings page was opened.
enum DeviceStatus: Hashable {
    case checking
    case connected(String)
    case failed(String)

    /// "Connected: Linux · 8 cores · 16 GB · up 3 days" from one sample.
    static func from(_ sample: RemoteRawSample) -> DeviceStatus {
        switch sample.os {
        case .linux, .macOS:
            let system = sample.os == .macOS ? "macOS" : "Linux"
            let parts = [
                L("Connected: %1$@ · %2$@ cores", system, "\(sample.cores)"),
                sample.memoryTotalBytes.map(Format.gigabytes),
                sample.uptime.map { L("up %@", Format.uptime($0)) },
            ]
            return .connected(parts.compactMap { $0 }.joined(separator: " · "))
        case .other:
            return .failed(L("Connected, but this system is not supported. Only Linux and macOS can be monitored."))
        }
    }

    /// The result in words, once there is one.
    var message: String? {
        switch self {
        case .checking: nil
        case .connected(let text), .failed(let text): text
        }
    }

    /// One sample's result as a status.
    static func from(_ result: Result<String, SSHRunnerError>) -> DeviceStatus {
        switch result {
        case .failure(let error): .failed(error.message)
        case .success(let output):
            RemoteMetricsParser.parse(output).map(from) ?? .failed(L("The server sent an unexpected response."))
        }
    }
}

/// Checks a device by taking one sample over SSH when its page opens, and remembers the result
/// while the settings window is open so the sidebar can show it as a dot. A connection the popover
/// keeps warm is reused, and one opened here closes on its own.
@MainActor
final class DeviceStatusStore: ObservableObject {
    @Published private(set) var statuses: [UUID: DeviceStatus] = [:]
    private var checks: [UUID: Task<Void, Never>] = [:]

    func status(of id: UUID) -> DeviceStatus? { statuses[id] }

    func check(_ device: RemoteDevice) {
        checks[device.id]?.cancel()
        set(.checking, for: device.id)
        checks[device.id] = Task {
            let result = await SSHRunner().run(device)
            guard !Task.isCancelled else { return }
            set(DeviceStatus.from(result), for: device.id)
            checks[device.id] = nil
        }
    }

    /// Stops checking a removed device and drops its status.
    func forget(_ id: UUID) {
        checks[id]?.cancel()
        checks[id] = nil
        statuses = statuses.filter { $0.key != id }
    }

    private func set(_ status: DeviceStatus, for id: UUID) {
        statuses = statuses.merging([id: status]) { _, new in new }
    }
}

/// Green when the device answered, red when it did not, grey while checking. With Differentiate
/// Without Color on, each state has its own symbol as well.
struct StatusDot: View {
    let status: DeviceStatus
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor

    var body: some View {
        Group {
            if withoutColor {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel(label)
    }

    private var symbol: String {
        switch status {
        case .checking: "ellipsis.circle"
        case .connected: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .checking: Color.secondary.opacity(0.5)
        case .connected: Color(nsColor: .systemGreen)
        case .failed: Color(nsColor: .systemRed)
        }
    }

    private var label: String {
        switch status {
        case .checking: L("Checking…")
        case .connected: L("Connected")
        case .failed: L("Not reachable")
        }
    }
}
