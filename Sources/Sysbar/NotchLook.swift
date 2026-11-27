import SysbarCore

/// How the island looks, as chosen in the settings: what fills it, and its icons' colours and size.
struct NotchLook: Equatable {
    var background: NotchBackground = .automatic
    var iconStyle: NotchIconStyle = .colored
    var iconSize: NotchIconSize = .medium
}
