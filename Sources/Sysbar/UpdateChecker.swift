import AppKit
import Security
import SysbarCore

/// Looks for a newer release on GitHub and, when the user agrees, installs it.
///
/// A check is one small HTTPS request for the latest release, made at most once a day (or when
/// "Check now" is pressed); nothing about this Mac is sent. Installing downloads the release
/// archive, accepts it only if it is signed by the same developer as the running app and holds the
/// expected version, swaps the app bundle in place and relaunches. When the app cannot be replaced
/// (no write access, or a development build) the release page is opened instead.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing
        case failed(String)
    }

    private enum Key {
        static let automatic = "checksForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let skipped = "skippedUpdateVersion"
    }

    /// Lets the menu bar settle after launch before the first automatic check.
    private static let firstCheckDelay: Duration = .seconds(30)
    /// How often the app looks at whether a day has passed since the last check.
    private static let wakeInterval: TimeInterval = 60 * 60
    private static let archiveName = "Sysbar.app"

    @Published private(set) var state: State = .idle
    /// The release suggested in the popover; nil when there is none or the user skipped it.
    @Published private(set) var offered: ReleaseInfo?
    @Published var isAutomatic: Bool {
        didSet {
            defaults.set(isAutomatic, forKey: Key.automatic)
            schedule()
        }
    }

    private let defaults: UserDefaults
    private var timer: Timer?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": "Sysbar/\(currentVersion?.description ?? "dev")"]
        return URLSession(configuration: configuration)
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isAutomatic = defaults.object(forKey: Key.automatic) as? Bool ?? true
    }

    var currentVersion: AppVersion? {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }

    func start() {
        schedule()
    }

    // MARK: Checking

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard isAutomatic else { return }
        let timer = Timer(timeInterval: Self.wakeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = Self.wakeInterval / 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { [weak self] in
            try? await Task.sleep(for: Self.firstCheckDelay)
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        guard isAutomatic, UpdateCheck.isDue(lastCheck: lastCheck, now: Date()) else { return }
        Task { await check(userInitiated: false) }
    }

    /// An automatic check respects a skipped version and stays quiet on failure; "Check now"
    /// shows every result.
    func check(userInitiated: Bool) async {
        guard state != .checking, state != .installing else { return }
        let previous = state
        state = .checking
        do {
            var request = URLRequest(url: UpdateCheck.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            // An install started meanwhile owns the state from here on.
            guard state == .checking else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = UpdateCheck.parseRelease(data) else {
                throw UpdateError.unexpectedReply
            }
            defaults.set(Date(), forKey: Key.lastCheck)
            let skipped = userInitiated ? nil : defaults.string(forKey: Key.skipped).flatMap(AppVersion.init)
            offered = UpdateCheck.offer(release, current: currentVersion, skipped: skipped)
            state = offered.map(State.available) ?? .upToDate
        } catch {
            guard state == .checking else { return }
            state = userInitiated ? .failed(L("Could not check for updates: %@", error.localizedDescription)) : previous
        }
    }

    /// Back to checking automatically, with no version skipped.
    func resetToDefaults() {
        defaults.removeObject(forKey: Key.skipped)
        isAutomatic = true
    }

    /// Hides the suggestion until a newer release than this one appears.
    func skip(_ release: ReleaseInfo) {
        defaults.set(release.version.description, forKey: Key.skipped)
        offered = nil
        state = .idle
    }

    func openReleasePage(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.pageURL)
    }

    // MARK: Installing

    func install(_ release: ReleaseInfo) async {
        guard state != .installing, state != .checking else { return }
        guard let archive = release.downloadURL, Self.canReplaceRunningApp else {
            openReleasePage(release)
            return
        }
        state = .installing
        do {
            let workspace = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: Bundle.main.bundleURL, create: true
            )
            defer { try? FileManager.default.removeItem(at: workspace) }
            let app = try await download(archive, into: workspace)
            try Self.verify(app, version: release.version)
            _ = try FileManager.default.replaceItemAt(Bundle.main.bundleURL, withItemAt: app)
            try Self.relaunch()
            // Still running: quitting was put off. The new copy is in place and opens once Sysbar quits.
            state = .failed(L("Quit and reopen Sysbar to finish updating."))
        } catch {
            state = .failed(L("The update could not be installed: %@", error.localizedDescription))
        }
    }

    private func download(_ archive: URL, into workspace: URL) async throws -> URL {
        let (file, response) = try await session.download(from: archive)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.downloadFailed }
        let zip = workspace.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: file, to: zip)
        let unpacked = workspace.appendingPathComponent("unpacked", isDirectory: true)
        try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        // Exactly one real folder named Sysbar.app: a symlink would be verified at its target but
        // installed as the link itself.
        let app = unpacked.appendingPathComponent(Self.archiveName, isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(atPath: unpacked.path)
        let values = try app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard contents == [Self.archiveName], values.isSymbolicLink == false, values.isDirectory == true else {
            throw UpdateError.unpackFailed
        }
        // Nobody else may change the copy between checking its signature and moving it in place.
        try await Self.run("/bin/chmod", ["-R", "go-w", unpacked.path])
        return app
    }

    /// Replacing needs write access to the app and its folder; a translocated copy (opened from a
    /// quarantined download without being moved) is read-only and temporary.
    private static var canReplaceRunningApp: Bool {
        let app = Bundle.main.bundleURL
        let manager = FileManager.default
        return !app.path.contains("/AppTranslocation/")
            && manager.isWritableFile(atPath: app.path)
            && manager.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// The new copy must satisfy the running app's own designated requirement (same identifier,
    /// same Developer ID team) and carry the version that was offered. A development build has an
    /// ad-hoc signature whose requirement no release can meet, so it never replaces itself.
    private static func verify(_ app: URL, version: AppVersion) throws {
        guard
            let bundle = Bundle(url: app),
            bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
            let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            AppVersion(shortVersion) == version
        else { throw UpdateError.wrongVersion }

        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard
            SecCodeCopySelf([], &running) == errSecSuccess, let running,
            SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
            SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
            SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate,
            SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess
        else { throw UpdateError.untrusted }
    }

    /// A small shell waits for this process to exit, then opens the new copy. The path is passed
    /// as an argument, never spliced into the script.
    private static func relaunch() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundleURL.path,
        ]
        try process.run()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.unpackFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum UpdateError: LocalizedError {
    case unexpectedReply, downloadFailed, unpackFailed, wrongVersion, untrusted

    var errorDescription: String? {
        switch self {
        case .unexpectedReply: L("GitHub sent an unexpected reply.")
        case .downloadFailed: L("The download failed.")
        case .unpackFailed: L("The download could not be opened.")
        case .wrongVersion: L("The download does not contain the expected version.")
        case .untrusted: L("The download is not signed by the Sysbar developer.")
        }
    }
}
