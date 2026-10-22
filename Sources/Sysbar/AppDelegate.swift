import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusController()
        if CommandLine.arguments.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusController?.openPopoverForTesting()
            }
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--popover-cycles"),
           flag + 1 < CommandLine.arguments.count, let cycles = Int(CommandLine.arguments[flag + 1]) {
            statusController?.cyclePopoverForTesting(times: cycles)
        }
        if let flag = CommandLine.arguments.firstIndex(of: "--settings-cycles"),
           flag + 1 < CommandLine.arguments.count, let cycles = Int(CommandLine.arguments[flag + 1]) {
            statusController?.cycleSettingsForTesting(times: cycles)
        }
        if CommandLine.arguments.contains("--update-now") {
            statusController?.updateNowForTesting()
        }
    }
}
