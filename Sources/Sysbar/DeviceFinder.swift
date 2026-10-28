import Foundation
import SystemConfiguration
import SysbarCore

/// Gathers the devices Settings › Devices suggests: Macs that announce Remote Login on this network,
/// through Bonjour, and the user's Tailscale machines, through the `tailscale` command. It only
/// listens and reads; it never connects to a device. Bonjour runs only while the page is shown.
@MainActor
final class DeviceFinder: NSObject, ObservableObject {
    private static let serviceType = "_ssh._tcp."
    private static let resolveTimeout: TimeInterval = 5
    private nonisolated static let tailscaleTimeout: TimeInterval = 5
    /// Where the Tailscale app and the Homebrew formula put the command.
    private nonisolated static let tailscalePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    @Published private(set) var local: [DeviceDiscovery.LocalService] = []
    @Published private(set) var tailscale: [DeviceDiscovery.TailscalePeer] = []
    @Published private(set) var isBrowsing = false

    private var browser: NetServiceBrowser?
    /// Services being resolved; NetService must be kept alive until it answers.
    private var resolving: [NetService] = []

    /// This Mac as Bonjour names it, so it is never suggested.
    let thisMac = DeviceDiscovery.LocalService(
        name: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "",
        host: (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" } ?? ""
    )

    func refreshTailscale() {
        Task {
            let output = await Self.runTailscaleStatus()
            tailscale = output.map(DeviceDiscovery.tailscalePeers(fromStatusJSON:)) ?? []
        }
    }

    /// Starts listening for SSH on this network. The first time, macOS asks to allow local network access.
    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: Self.serviceType, inDomain: "local.")
        self.browser = browser
        isBrowsing = true
    }

    func stopBrowsing() {
        browser?.stop()
        browser = nil
        resolving.forEach { $0.stop() }
        resolving = []
        isBrowsing = false
    }

    private func resolved(_ service: NetService) {
        resolving.removeAll { $0 === service }
        guard let host = service.hostName else { return }
        let found = DeviceDiscovery.LocalService(name: service.name, host: host)
        if !local.contains(found) { local = local + [found] }
    }

    private func removed(_ service: NetService) {
        resolving.removeAll { $0 === service }
        local = local.filter { $0.name != service.name }
    }

    /// `tailscale status --json`, or nil when Tailscale is not installed, not running or too slow.
    private nonisolated static func runTailscaleStatus() async -> Data? {
        guard let path = tailscalePaths.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["status", "--json"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + tailscaleTimeout, execute: watchdog)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()
                continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
            }
        }
    }
}

// The browser is created on the main thread, so its delegate is called there too.
extension DeviceFinder: NetServiceBrowserDelegate, NetServiceDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        MainActor.assumeIsolated {
            service.delegate = self
            resolving.append(service)
            service.resolve(withTimeout: Self.resolveTimeout)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        MainActor.assumeIsolated { removed(service) }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        MainActor.assumeIsolated { resolved(sender) }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        MainActor.assumeIsolated { resolving.removeAll { $0 === sender } }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        MainActor.assumeIsolated { stopBrowsing() }
    }
}
