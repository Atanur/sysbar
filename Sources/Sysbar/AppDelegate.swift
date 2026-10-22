import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Settings domain used before the app was renamed to Sysbar.
    private static let legacyDefaultsDomain = "com.atanur.menumon"

    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.migrateLegacyDefaults()
        statusController = StatusController()
        if CommandLine.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusController?.openPopoverForTesting()
            }
        }
    }

    /// Copies the settings saved under the old name the first time Sysbar runs, so devices and
    /// choices survive the rename. The old domain is left in place untouched.
    private static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        guard
            let domain = Bundle.main.bundleIdentifier,
            defaults.persistentDomain(forName: domain)?.isEmpty ?? true,
            let legacy = defaults.persistentDomain(forName: legacyDefaultsDomain), !legacy.isEmpty
        else { return }
        defaults.setPersistentDomain(legacy, forName: domain)
    }
}
