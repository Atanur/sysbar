import AppKit
import SwiftUI

/// Hosts the panel's SwiftUI content and says when the height it wants changes. A hosting controller's
/// `preferredContentSize` is not announced to key-value observers, so the island, which follows the
/// content's height from page to page, is told here, after the content has been laid out.
final class PanelHostingController<Content: View>: NSHostingController<Content> {
    /// Called, on the next turn of the run loop, when the content wants another height.
    var onHeightChange: (() -> Void)?
    private var height: CGFloat = 0

    override func viewDidLayout() {
        super.viewDidLayout()
        check(view.fittingSize.height)
    }

    /// Set by SwiftUI as the content changes within a page, such as another stash chosen, which lays
    /// nothing out again in a view whose frame the island has fixed.
    override var preferredContentSize: NSSize {
        didSet { check(preferredContentSize.height) }
    }

    private func check(_ wanted: CGFloat) {
        guard onHeightChange != nil, wanted > 0, abs(wanted - height) > 0.5 else { return }
        height = wanted
        DispatchQueue.main.async { [weak self] in self?.onHeightChange?() }
    }
}
