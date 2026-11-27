import SwiftUI
import SysbarCore

/// What the open panel needs to know of the island's strip: the icons' size, which its settings
/// button shares. The island sets it before the panel is built and whenever the screens change.
@MainActor
final class NotchRowModel: ObservableObject {
    @Published var iconSide: CGFloat = NotchGeometry.featureIconSide
    /// The panel's height as last laid out, 0 until it is. Told by the panel itself: a change within a
    /// page, such as another stash chosen, reaches no hosting-controller size the island could watch.
    private(set) var contentHeight: CGFloat = 0
    var onContentHeight: () -> Void = {}

    func report(height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        onContentHeight()
    }

    func forgetHeight() { contentHeight = 0 }
}

/// The open panel's laid-out height, passed up to `NotchRowModel`.
struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
