import CoreGraphics

/// Where Sysbar lives: its menu bar item, or the top of the screen around the notch. Never both.
public enum SysbarPlacement: String, CaseIterable, Sendable {
    case menuBar, notch
}

/// Where the top-of-screen island goes on one screen, in AppKit screen coordinates (origin at the
/// bottom left). Nothing here is fixed: the notch's size depends on the model and on the display's
/// scaling, so it is measured from the screen each time the screens change.
///
/// With a notch, the island is a black shape around it: readouts in the left ear, the feature icons
/// in the right, opening into a panel that hangs from the strip's bottom edge, or the stash picker. Without one (an external display, a Mac without a notch, or a lid
/// closed), it is a small glass capsule at the top centre that opens into a card.
public struct NotchGeometry: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case notch, capsule
    }

    /// Room around an ear's content, and the most an ear may take: the area beside the notch holds
    /// the app's menus on the left and other menu bar items on the right.
    public static let earPadding: CGFloat = 14
    public static let maxEarWidth: CGFloat = 170
    /// The capsule's distance from the top edge, and from the menu bar's bottom edge.
    /// One point keeps the 22-point readouts whole in a 24-point menu bar.
    public static let capsuleInset: CGFloat = 1
    /// Between the capsule's two halves.
    public static let capsuleGap: CGFloat = 10
    /// Around the content of the open panel.
    public static let contentInset: CGFloat = 10
    /// For a screen whose menu bar is hidden and has no notch to go by.
    public static let standardBarHeight: CGFloat = 24
    /// Readouts in the left ear, the battery among them; the rest show once the island opens.
    public static let leftEarReadouts = 3
    /// The tallest the closed row's content gets at medium size: the readouts' image is this high.
    public static let contentHeight: CGFloat = 22
    /// The narrowest a capsule gets, so one with nothing in it can still be pointed at.
    public static let capsuleMinimumWidth: CGFloat = 44
    /// Between two readouts in the left ear.
    public static let readoutGap: CGFloat = 10
    /// One feature icon in the right ear is a square this wide at medium size, with this much between two.
    public static let featureIconSide: CGFloat = 22
    public static let featureIconGap: CGFloat = 2
    /// How far the System tab's capsule reaches past the readouts on either side.
    public static let highlightPadding: CGFloat = 6
    /// Between the notch and what sits beside it: the readouts closed, the tabs open.
    public static let notchClearance: CGFloat = 6

    public let shape: Shape
    public let screen: CGRect
    /// The notch, or for a capsule the top centre of the screen, as wide as nothing.
    public let anchor: CGRect
    /// The height of the menu bar, or of the notch while the menu bar is hidden.
    public let barHeight: CGFloat

    public static func make(
        frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?
    ) -> NotchGeometry {
        let menuBar = frame.maxY - visibleFrame.maxY
        let barHeight = menuBar > 0 ? menuBar : (safeTop > 0 ? safeTop : standardBarHeight)
        // The areas beside the notch are what measure it; a screen reporting an inset without them
        // is not a notch to wrap around.
        if safeTop > 0, let leftArea, let rightArea {
            let width = frame.width - leftArea.width - rightArea.width
            if width > 0 {
                let anchor = CGRect(x: frame.minX + leftArea.width, y: frame.maxY - safeTop, width: width, height: safeTop)
                return NotchGeometry(shape: .notch, screen: frame, anchor: anchor, barHeight: barHeight)
            }
        }
        let anchor = CGRect(x: frame.midX, y: frame.maxY - barHeight, width: 0, height: barHeight)
        return NotchGeometry(shape: .capsule, screen: frame, anchor: anchor, barHeight: barHeight)
    }

    /// The closed island, with `left` and `right` points of content in its two halves.
    public func collapsedFrame(left: CGFloat, right: CGFloat) -> CGRect {
        switch shape {
        case .notch:
            let leftEar = left > 0 ? min(left + Self.earPadding, Self.maxEarWidth) : 0
            let rightEar = right > 0 ? min(right + Self.earPadding, Self.maxEarWidth) : 0
            return CGRect(
                x: anchor.minX - leftEar, y: anchor.minY,
                width: leftEar + anchor.width + rightEar, height: anchor.height
            )
        case .capsule:
            let height = barHeight - 2 * Self.capsuleInset
            let width = max(
                min(Self.capsuleRowWidth(left: left, right: right) + 2 * Self.earPadding, 2 * Self.maxEarWidth),
                Self.capsuleMinimumWidth
            )
            return CGRect(x: screen.midX - width / 2, y: screen.maxY - Self.capsuleInset - height, width: width, height: height)
        }
    }

    /// The open island: the strip (`collapsed`, the closed row with whatever the open one adds) on top
    /// and the panel for `content` hanging from its bottom edge, centred on the notch and kept on
    /// screen. The window is as wide as the panel, which is never narrower than the strip.
    public func expandedFrame(content: CGSize, collapsed: CGRect) -> CGRect {
        // Wide enough that both ears still fit around the notch.
        let width = min(max(content.width + 2 * Self.contentInset, minimumOpenWidth(collapsed)), screen.width)
        let height = min(collapsed.height + content.height + Self.contentInset, collapsed.maxY - screen.minY)
        return hanging(width: width, height: height, collapsed: collapsed)
    }

    /// The island while it offers stashes for dragged files: `size` is the whole picker, its closed
    /// row included, as `ShelfPickerLayout` measures it.
    public func pickerFrame(size: CGSize, collapsed: CGRect) -> CGRect {
        let width = min(max(size.width, minimumOpenWidth(collapsed)), screen.width)
        return hanging(width: width, height: min(size.height, collapsed.maxY - screen.minY), collapsed: collapsed)
    }

    /// The width an open island needs to keep both ears around the notch: give it to the picker's
    /// layout as its minimum, so the tiles are centred in the island.
    public func minimumOpenWidth(_ collapsed: CGRect) -> CGFloat {
        2 * max(anchor.midX - collapsed.minX, collapsed.maxX - anchor.midX)
    }

    private func hanging(width: CGFloat, height: CGFloat, collapsed: CGRect) -> CGRect {
        let x = min(max(anchor.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: collapsed.maxY - height, width: width, height: height)
    }

    /// Which readouts go in the left ear, by index and in their menu bar order: at most `limit`, the
    /// battery first when it is shown, then the system's readouts as they come. With `widths` (each readout's own, `gap` between two) a readout
    /// that would not fit the `room` the ear has for them (what icons sharing it leave) ends the list,
    /// so the ear never grows past `maxEarWidth`.
    public static func earReadouts(
        _ slots: [MenuBarSlot], limit: Int = leftEarReadouts,
        widths: [CGFloat]? = nil, gap: CGFloat = readoutGap, room: CGFloat = earRoom
    ) -> [Int] {
        let priority = slots.indices.filter { slots[$0] == .battery } + slots.indices.filter { slots[$0] != .battery }
        var taken: [Int] = []
        var used: CGFloat = 0
        for index in priority {
            guard taken.count < limit else { break }
            if let widths {
                let next = used + (taken.isEmpty ? 0 : gap) + widths[index]
                guard next <= room else { break }
                used = next
            }
            taken.append(index)
        }
        return taken.sorted()
    }

    /// The width of `count` feature icons of `side` points side by side, the right ear's content.
    public static func featureIconsWidth(_ count: Int, side: CGFloat = featureIconSide) -> CGFloat {
        count > 0 ? CGFloat(count) * side + CGFloat(count - 1) * featureIconGap : 0
    }

    /// How much the readouts and icons are scaled in a row `rowHeight` tall: the chosen size, but
    /// never past what the row holds, so a capsule on a 24 pt menu bar keeps them whole.
    public static func contentScale(_ size: NotchIconSize, rowHeight: CGFloat) -> CGFloat {
        min(size.scale, max(rowHeight / contentHeight, 0))
    }

    /// A feature icon's side at `scale`.
    public static func featureIconSide(scale: CGFloat) -> CGFloat {
        (featureIconSide * scale).rounded()
    }

    /// The width of a capsule's one row of `left` and `right` points of content: a gap between them
    /// only when both halves have something.
    public static func capsuleRowWidth(left: CGFloat, right: CGFloat) -> CGFloat {
        left + right + (left > 0 && right > 0 ? capsuleGap : 0)
    }
}
