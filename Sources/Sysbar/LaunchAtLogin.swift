import ServiceManagement

/// Registers the app as a login item. This needs the app to be a proper bundle (see
/// `scripts/bundle.sh`); it may be refused for an unsigned copy run from a build folder.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
