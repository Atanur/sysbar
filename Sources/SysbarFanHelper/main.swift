import CSystemBridge
import Foundation
import IOKit.pwr_mgt
import SysbarCore

// Sysbar's helper. launchd runs it as root when Sysbar connects (Sysbar registers it once with
// SMAppService), because only root may write the SMC or change system power settings. It does
// two things: run every fan at a chosen speed (or hand them back to macOS), and keep the Mac
// awake with its lid closed (LidAwakeService, which has its own lease and is undone separately).
// It accepts connections only from Sysbar signed by the same team. The fans go back to
// automatic whenever:
// - setting them fails part way,
// - Sysbar stops renewing manual mode (FanControlLimits.leaseSeconds), e.g. it hangs,
// - Sysbar disconnects (quits or crashes),
// - the Mac goes to sleep (manual requests are refused until it has woken),
// - the helper is stopped.
// With no client it exits.

/// Applies fan requests on one serial queue, so requests, the lease, sleep handling and
/// disconnects never interleave.
final class FanService: @unchecked Sendable {
    static let shared = FanService()

    /// Attempts at switching a fan's mode; the system may hold a fan for a moment first.
    private static let modeAttempts = 30
    private static let modeRetryMicroseconds: useconds_t = 100_000
    /// Attempts at handing fans back before giving up on one.
    private static let automaticAttempts = 3

    let queue = DispatchQueue(label: "com.atanur.sysbar.fanhelper.fans")
    private var lease: DispatchSourceTimer?
    /// Set between the sleep notice and wake; manual requests are refused meanwhile.
    private var isAsleep = false

    /// Must run on `queue`.
    func applyManual(_ fraction: Double) -> String? {
        guard fraction.isFinite, (0...1).contains(fraction) else { return "The requested speed is out of range." }
        guard !isAsleep else { return "The Mac is going to sleep." }
        let fans = Self.fanIndices()
        guard !fans.isEmpty else { return "This Mac has no fans." }

        if let failure = setFans(fans, to: fraction) {
            applyAutomatic()
            return failure
        }
        renewLease()
        return nil
    }

    /// Must run on `queue`. Safe to call when already automatic.
    @discardableResult
    func applyAutomatic() -> String? {
        lease?.cancel()
        lease = nil
        var failed = false
        for index in Self.fanIndices() where !Self.setMode(0, of: index, attempts: Self.automaticAttempts) {
            failed = true
        }
        if SMC.exists("Ftst") { _ = SMC.write(uint8: 0, to: "Ftst") }
        return failed ? "A fan did not return to automatic control." : nil
    }

    /// Must run on `queue`.
    func setAsleep(_ asleep: Bool) {
        isAsleep = asleep
        if asleep { applyAutomatic() }
    }

    private func setFans(_ fans: [Int], to fraction: Double) -> String? {
        if SMC.exists("Ftst"), !SMC.write(uint8: 1, to: "Ftst") {
            return "The fans could not be unlocked for manual control."
        }
        for index in fans {
            guard
                let minimum = SMC.float("F\(index)Mn"), let maximum = SMC.float("F\(index)Mx"),
                let target = FanControlLimits.targetRPM(fraction: fraction, minimum: minimum, maximum: maximum)
            else { return "Fan \(index + 1) reported an unusable speed range." }
            guard Self.setMode(1, of: index, attempts: Self.modeAttempts) else {
                return "Fan \(index + 1) did not accept manual control."
            }
            guard SMC.write(float: Float(target), to: "F\(index)Tg") else {
                return "Fan \(index + 1) did not accept the new speed."
            }
        }
        return nil
    }

    /// Manual mode lapses unless the app asks again before the lease runs out.
    private func renewLease() {
        lease?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + FanControlLimits.leaseSeconds)
        timer.setEventHandler { [weak self] in self?.applyAutomatic() }
        timer.resume()
        lease = timer
    }

    /// The fans to drive: as many as `FNum` reports, or, if it cannot be read, every index that
    /// has a speed range, so a failed read never skips a fan.
    private static func fanIndices() -> [Int] {
        if let count = SMC.uint8("FNum") { return Array(0..<min(Int(count), FanControlLimits.maximumFans)) }
        return (0..<FanControlLimits.maximumFans).filter { SMC.float("F\($0)Mx") != nil }
    }

    /// Writes a fan's mode (0 automatic, 1 manual) and reads it back, retrying while the system
    /// still holds the fan.
    private static func setMode(_ mode: UInt8, of index: Int, attempts: Int) -> Bool {
        let key = "F\(index)Md"
        for _ in 0..<attempts {
            if SMC.write(uint8: mode, to: key), SMC.uint8(key) == mode { return true }
            usleep(modeRetryMicroseconds)
        }
        return false
    }
}

/// Typed access to the few SMC keys the helper touches. Writes name the type the key must have.
enum SMC {
    static func exists(_ key: String) -> Bool { raw(key) != nil }

    static func uint8(_ key: String) -> UInt8? {
        guard let bytes = raw(key), bytes.count == 1 else { return nil }
        return bytes[0]
    }

    static func float(_ key: String) -> Double? {
        var value: Float = 0
        guard smc_read_float(key, &value), value.isFinite else { return nil }
        return Double(value)
    }

    static func write(uint8 value: UInt8, to key: String) -> Bool {
        smc_write_bytes(key, "ui8 ", [value], 1)
    }

    /// SMC floats are 32-bit and little-endian, the same order as Apple silicon itself.
    static func write(float value: Float, to key: String) -> Bool {
        guard value.isFinite else { return false }
        let bytes = withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
        return smc_write_bytes(key, "flt ", bytes, UInt32(bytes.count))
    }

    private static func raw(_ key: String) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        var type: UInt32 = 0
        guard smc_read_bytes(key, &bytes, UInt32(bytes.count), &size, &type) else { return nil }
        return Array(bytes.prefix(Int(size)))
    }
}

/// One verified client. It counts as connected only from its first request, which XPC delivers
/// only after the client has met the code signing requirement; a rejected connection therefore
/// never counts and cannot make the helper restore and exit.
final class ClientSession: NSObject, FanControlProtocol, @unchecked Sendable {
    private weak var listener: Listener?
    /// Touched on the fan queue only.
    private var counted = false

    init(listener: Listener) {
        self.listener = listener
    }

    func setManual(fraction: Double, reply: @escaping (String?) -> Void) {
        FanService.shared.queue.async {
            self.countOnce()
            reply(FanService.shared.applyManual(fraction))
        }
    }

    func setAutomatic(reply: @escaping (String?) -> Void) {
        FanService.shared.queue.async {
            self.countOnce()
            reply(FanService.shared.applyAutomatic())
        }
    }

    func setLidAwake(enabled: Bool, reply: @escaping (String?) -> Void) {
        FanService.shared.queue.async {
            self.countOnce()
            reply(LidAwakeService.shared.set(enabled: enabled))
        }
    }

    /// Must run on the fan queue.
    func ended() {
        guard counted else { return }
        counted = false
        listener?.clientLeft()
    }

    private func countOnce() {
        guard !counted else { return }
        counted = true
        listener?.clientJoined()
    }
}

/// Accepts Sysbar's connections. When the last client that made a request goes away, the fans
/// go back to automatic and the helper exits; launchd starts it again on the next connection.
final class Listener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    /// launchd starts the helper because a connection is waiting; with no client by then, it leaves.
    static let idleExitSeconds = 30.0

    private let team: String?
    /// Touched on the fan queue only.
    private var clients = 0

    init(team: String?) {
        self.team = team
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let team else { return false }
        connection.setCodeSigningRequirement(
            FanControlLimits.requirement(identifier: FanControlLimits.appIdentifier, team: team)
        )
        let session = ClientSession(listener: self)
        connection.exportedInterface = NSXPCInterface(with: FanControlProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { FanService.shared.queue.async { session.ended() } }
        connection.resume()
        return true
    }

    /// Must run on the fan queue.
    func clientJoined() {
        clients += 1
    }

    /// Must run on the fan queue.
    func clientLeft() {
        clients -= 1
        if clients <= 0 { restoreAndExit() }
    }

    func exitIfIdle() {
        FanService.shared.queue.async {
            if self.clients <= 0 { self.restoreAndExit() }
        }
    }

    /// Must run on the fan queue.
    private func restoreAndExit() {
        FanService.shared.applyAutomatic()
        LidAwakeService.shared.restore()
        exit(0)
    }
}

/// Fans go back to automatic just before the Mac sleeps, and stay there until it has woken. A
/// "can the system sleep?" query is only acknowledged, since that sleep may still be cancelled.
final class SleepWatcher: @unchecked Sendable {
    /// `kIOMessageSystemWillSleep`, `kIOMessageCanSystemSleep` and `kIOMessageSystemHasPoweredOn`
    /// from IOMessage.h, which Swift cannot import because they are function-like macros.
    private static let willSleep: UInt32 = 0xE000_0280
    private static let canSleep: UInt32 = 0xE000_0270
    private static let hasPoweredOn: UInt32 = 0xE000_0300

    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    fileprivate var rootPort: io_connect_t = 0

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &port, { context, _, messageType, argument in
            guard let context else { return }
            let watcher = Unmanaged<SleepWatcher>.fromOpaque(context).takeUnretainedValue()
            switch messageType {
            case SleepWatcher.willSleep:
                FanService.shared.queue.sync { FanService.shared.setAsleep(true) }
                IOAllowPowerChange(watcher.rootPort, Int(bitPattern: argument))
            case SleepWatcher.canSleep:
                IOAllowPowerChange(watcher.rootPort, Int(bitPattern: argument))
            case SleepWatcher.hasPoweredOn:
                FanService.shared.queue.async { FanService.shared.setAsleep(false) }
            default:
                break
            }
        }, &notifier)
        if let port {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        }
    }
}

let listener = Listener(team: FanControlLimits.signingTeam())
let service = NSXPCListener(machServiceName: FanControlLimits.helperLabel)
service.delegate = listener
service.resume()

let sleepWatcher = SleepWatcher()
sleepWatcher.start()

signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    FanService.shared.queue.sync {
        _ = FanService.shared.applyAutomatic()
        LidAwakeService.shared.restore()
    }
    exit(0)
}
termination.resume()

DispatchQueue.main.asyncAfter(deadline: .now() + Listener.idleExitSeconds) { listener.exitIfIdle() }
RunLoop.main.run()
