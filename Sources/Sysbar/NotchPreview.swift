import AppKit
import SysbarCore
import SwiftUI

/// The top of this Mac's screen as the island will look on it, drawn from fixed sample values: the
/// wallpaper, the menu bar, the notch (or the capsule), and the island closed or open with the panel
/// hanging from its strip. Everything is laid out in the screen's real points, with the real
/// geometry, and the whole picture is scaled by one factor, so the proportions are the screen's own.
struct NotchPreview: View {
    @ObservedObject var preferences: Preferences
    @State private var open: Bool
    /// The shape to show instead of the one this Mac's screen has.
    private let forcedShape: NotchGeometry.Shape?

    /// How much the picture is scaled: as much as the settings page has room for, up to this.
    private static let preferredScale: CGFloat = 0.8
    private static let closedCorner: CGFloat = 10
    private static let notchCorner: CGFloat = 10
    /// What the open panel's bottom corners are drawn with, as the island's are.
    private static let openCorner = NotchOutline.preferredCorner
    /// The wallpaper under the closed island, below the menu bar.
    private static let wallpaperMargin: CGFloat = 22
    /// A panel's inset from the screen's side edges, for a scale that fits it.
    private static let sideMargin: CGFloat = 8

    init(preferences: Preferences, open: Bool = false, shape: NotchGeometry.Shape? = nil) {
        self.preferences = preferences
        _open = State(initialValue: open)
        forcedShape = shape
    }

    /// An item in an ear, with the readouts' image when it is the System item with bars to show.
    private struct Entry {
        let core: NotchEarEntry
        let image: NSImage?
    }

    /// Where everything is, in the picture's points: origin at the top left of the visible part of
    /// the screen, which is centred on the notch.
    private struct Layout {
        let geometry: NotchGeometry
        let width: CGFloat
        /// The strip: the closed island, or the row the open one keeps on top.
        let strip: CGRect
        /// The open panel including the strip, nil when closed.
        let panel: CGRect?
        let notch: CGRect
        let height: CGFloat
        let leftCores: [NotchEarEntry]
        let rightCores: [NotchEarEntry]
    }

    var body: some View {
        let geometry = Self.geometry(shape: forcedShape)
        let shape = geometry.shape
        let fill = preferences.notchBackground.fill(for: shape)
        let rowHeight = geometry.collapsedFrame(left: 0, right: 0).height
        let size = NotchGeometry.contentScale(preferences.notchIconSize, rowHeight: rowHeight)
        let monochrome = preferences.notchIconStyle == .monochrome
        let ears = entries(size: size, monochrome: monochrome)
        let titles = { (entries: [Entry]) in entries.compactMap { $0.core.item?.section.title }.joined(separator: ", ") }
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                picture(geometry: geometry, fill: fill, size: size, monochrome: monochrome, ears: ears, available: proxy.size.width)
            }
            .frame(height: Self.pictureHeight(geometry: geometry, ears: ears, size: size, open: open, preferences: preferences) * Self.preferredScale)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // Read as one element, rather than as an image and some symbols.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Notch preview"))
            .accessibilityValue("\(NotchEar.left.title): \(titles(ears.left)). \(NotchEar.right.title): \(titles(ears.right))")
            Picker(L("Preview"), selection: $open) {
                Text(L("Closed")).tag(false)
                Text(L("Open")).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(10)
    }

    // MARK: Geometry

    /// The screen the preview imitates: the built-in one with a notch if there is one, otherwise the
    /// main screen, which then gets the capsule.
    static func geometry(shape: NotchGeometry.Shape? = nil) -> NotchGeometry {
        let screens = NSScreen.screens
        let notched = screens.first { $0.safeAreaInsets.top > 0 }
        let screen = shape == .capsule ? (screens.first ?? notched) : (notched ?? screens.first)
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1512, height: 945)
        let capsule = shape == .capsule
        return NotchGeometry.make(
            frame: frame, visibleFrame: visible, safeTop: capsule ? 0 : screen?.safeAreaInsets.top ?? 0,
            leftArea: capsule ? nil : screen?.auxiliaryTopLeftArea, rightArea: capsule ? nil : screen?.auxiliaryTopRightArea
        )
    }

    /// The height of the picture at its natural scale; the open one is the taller.
    private static func pictureHeight(
        geometry: NotchGeometry, ears: (left: [Entry], right: [Entry]), size: CGFloat, open: Bool, preferences: Preferences
    ) -> CGFloat {
        let row = geometry.collapsedFrame(left: 0, right: 0)
        let top = geometry.screen.maxY - row.minY - row.height
        guard open else { return geometry.barHeight + top + wallpaperMargin }
        let side = NotchGeometry.featureIconSide(scale: size)
        return geometry.barHeight + NotchPreviewPanel.height(preferences: preferences, iconSide: side) + NotchGeometry.contentInset + wallpaperMargin
    }

    private func layout(geometry: NotchGeometry, ears: (left: [Entry], right: [Entry]), width: CGFloat, size: CGFloat) -> Layout {
        let leftWidth = NotchGeometry.earWidth(ears.left.map(\.core))
        let rightWidth = NotchGeometry.earWidth(ears.right.map(\.core))
        let collapsed = geometry.collapsedFrame(left: leftWidth, right: rightWidth)
        // The visible part is centred on the notch; screen x becomes picture x by this shift.
        let shift = geometry.anchor.midX - width / 2
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - shift, y: geometry.screen.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let notch = local(geometry.anchor)
        var panel: CGRect?
        if open {
            let side = NotchGeometry.featureIconSide(scale: size)
            let content = CGSize(width: PopoverView.wideWidth, height: NotchPreviewPanel.height(preferences: preferences, iconSide: side))
            panel = local(geometry.expandedFrame(content: content, collapsed: collapsed))
        }
        let height = Self.pictureHeight(geometry: geometry, ears: ears, size: size, open: open, preferences: preferences)
        return Layout(geometry: geometry, width: width, strip: local(collapsed), panel: panel, notch: notch, height: height,
            leftCores: ears.left.map(\.core), rightCores: ears.right.map(\.core))
    }

    // MARK: Picture

    private func picture(
        geometry: NotchGeometry, fill: NotchBackground.Fill, size: CGFloat, monochrome: Bool,
        ears: (left: [Entry], right: [Entry]), available: CGFloat
    ) -> some View {
        let probe = layout(geometry: geometry, ears: ears, width: available / Self.preferredScale, size: size)
        // Shrinks only when the open panel would not fit the room.
        let panelWidth = probe.panel?.width ?? probe.strip.width
        let scale = min(Self.preferredScale, max(available - 2 * Self.sideMargin, 1) / panelWidth)
        let width = available / scale
        let frame = layout(geometry: geometry, ears: ears, width: width, size: size)
        let dark = fill.isDark || NSApp.effectiveAppearance.isDark
        let menuDark = NSApp.effectiveAppearance.isDark
        return ZStack(alignment: .topLeading) {
            wallpaper(dark: menuDark)
            menuBar(frame, dark: menuDark)
            island(frame, fill: fill, size: size, monochrome: monochrome, ears: ears, dark: dark)
        }
        .frame(width: width, height: frame.height, alignment: .topLeading)
        .clipped()
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: available, height: frame.height * scale, alignment: .topLeading)
    }

    private func wallpaper(dark: Bool) -> some View {
        let colors: [Color] = dark
            ? [Color(red: 0.09, green: 0.11, blue: 0.30), Color(red: 0.34, green: 0.17, blue: 0.52), Color(red: 0.83, green: 0.38, blue: 0.42)]
            : [Color(red: 0.36, green: 0.55, blue: 0.86), Color(red: 0.62, green: 0.58, blue: 0.90), Color(red: 0.98, green: 0.74, blue: 0.62)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The menu bar's row with plausible items, subdued, and only as many as fit beside the island.
    private func menuBar(_ layout: Layout, dark: Bool) -> some View {
        let ink = dark ? Color.white : Color.black
        let bar = layout.geometry.barHeight
        let margin: CGFloat = 16
        let leftRoom = layout.strip.minX - 2 * margin
        let rightRoom = layout.width - layout.strip.maxX - 2 * margin
        let left: [(String, CGFloat)] = [("apple.logo", 14), ("Finder", 46), ("File", 24), ("Edit", 26), ("View", 32), ("Go", 20), ("Window", 52), ("Help", 30)]
        let right: [(String, CGFloat)] = [("9:41", 36), ("Tue", 26), ("switch.2", 18), ("wifi", 18), ("magnifyingglass", 16)]
        let leftItems = Self.fitting(left, room: leftRoom, gap: 14)
        let rightItems = Self.fitting(right, room: rightRoom, gap: 12)
        return ZStack(alignment: .top) {
            Rectangle().fill(dark ? Color.black.opacity(0.28) : Color.white.opacity(0.30)).frame(height: bar)
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    ForEach(Array(leftItems.enumerated()), id: \.offset) { index, item in
                        if item.0 == "apple.logo" { Image(systemName: "apple.logo").font(.system(size: 14, weight: .medium)) }
                        else { Text(item.0).font(.system(size: 13, weight: index == 1 ? .bold : .regular)) }
                    }
                }
                .padding(.leading, margin)
                .frame(width: max(layout.strip.minX, 0), alignment: .leading)
                .clipped()
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    ForEach(Array(rightItems.reversed().enumerated()), id: \.offset) { _, item in
                        if item.0.first?.isNumber == true || item.0 == "Tue" { Text(item.0).font(.system(size: 13)) }
                        else { Image(systemName: item.0).font(.system(size: 13)) }
                    }
                }
                .padding(.trailing, margin)
                .frame(width: max(layout.width - layout.strip.maxX, 0), alignment: .trailing)
                .clipped()
            }
            .frame(height: bar)
        }
        .foregroundStyle(ink.opacity(0.78))
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// The items from the front of `items` that fit `room`, with `gap` between them.
    private static func fitting(_ items: [(String, CGFloat)], room: CGFloat, gap: CGFloat) -> [(String, CGFloat)] {
        var used: CGFloat = 0
        var kept: [(String, CGFloat)] = []
        for item in items {
            let next = used + item.1 + (kept.isEmpty ? 0 : gap)
            guard next <= room else { break }
            used = next
            kept.append(item)
        }
        return kept
    }

    // MARK: Island

    @ViewBuilder
    private func island(
        _ layout: Layout, fill: NotchBackground.Fill, size: CGFloat, monochrome: Bool,
        ears: (left: [Entry], right: [Entry]), dark: Bool
    ) -> some View {
        let shape = layout.geometry.shape
        let strip = layout.strip
        let outline = outline(layout)
        let origin = layout.panel?.origin ?? strip.origin
        ZStack(alignment: .topLeading) {
            switch fill {
            case .black: Path(outline).fill(.black).offset(x: origin.x, y: origin.y)
            case .glass: Path(outline).fill(.ultraThinMaterial).offset(x: origin.x, y: origin.y)
            }
            if shape == .notch {
                // The notch itself: black whatever fills the island.
                UnevenRoundedRectangle(bottomLeadingRadius: Self.notchCorner, bottomTrailingRadius: Self.notchCorner, style: .continuous)
                    .fill(.black)
                    .frame(width: layout.notch.width, height: layout.notch.height)
                    .offset(x: layout.notch.minX, y: layout.notch.minY)
            }
            earRow(ears.left, layout: layout, size: size, monochrome: monochrome, dark: dark, ear: .left)
            earRow(ears.right, layout: layout, size: size, monochrome: monochrome, dark: dark, ear: .right)
            if let panel = layout.panel {
                NotchPreviewPanel(preferences: preferences, iconSide: NotchGeometry.featureIconSide(scale: size))
                    .offset(x: panel.minX + (panel.width - PopoverView.wideWidth) / 2, y: strip.maxY)
            }
        }
        .foregroundStyle(.primary)
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    /// The island's outline, as the island itself draws it: in its own coordinates, origin at its top left.
    private func outline(_ layout: Layout) -> CGPath {
        let shape = layout.geometry.shape
        guard let panel = layout.panel else {
            return IslandOutline.closed(size: layout.strip.size, shape: shape, corner: Self.closedCorner)
        }
        let span = (layout.strip.minX - panel.minX)...(layout.strip.maxX - panel.minX)
        return IslandOutline.popup(size: panel.size, shape: shape, strip: span, header: layout.strip.height, bottomCorner: Self.openCorner)
    }

    /// One ear's items, placed as the island does: the left one ends clear of the notch, the right
    /// one starts clear of it; a capsule's two halves are one row.
    private func earRow(
        _ entries: [Entry], layout: Layout, size: CGFloat, monochrome: Bool, dark: Bool, ear: NotchEar
    ) -> some View {
        let cores = entries.map(\.core)
        let leftWidth = NotchGeometry.earWidth(layout.leftCores)
        let width = NotchGeometry.earWidth(cores)
        let x: CGFloat
        if layout.geometry.shape == .notch {
            x = ear == .left ? layout.notch.minX - NotchGeometry.notchClearance - width : layout.notch.maxX + NotchGeometry.notchClearance
        } else {
            let rightWidth = NotchGeometry.earWidth(layout.rightCores)
            let start = layout.notch.midX - NotchGeometry.capsuleRowWidth(left: leftWidth, right: rightWidth) / 2
            x = ear == .left ? start : start + leftWidth + (leftWidth > 0 && rightWidth > 0 ? NotchGeometry.capsuleGap : 0)
        }
        let side = NotchGeometry.featureIconSide(scale: size)
        let offsets = NotchGeometry.earOffsets(cores)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(entries.enumerated()), id: \.element.core.slot) { index, entry in
                item(entry, size: size, side: side, monochrome: monochrome, dark: dark)
                    .offset(x: offsets[index])
            }
        }
        .frame(width: width, height: layout.strip.height, alignment: .topLeading)
        .offset(x: x, y: layout.strip.minY)
    }

    private func item(_ entry: Entry, size: CGFloat, side: CGFloat, monochrome: Bool, dark: Bool) -> some View {
        Group {
            if let image = entry.image {
                let drawn = Self.drawn(image, dark: dark)
                Image(nsImage: drawn)
                    .renderingMode(drawn.isTemplate ? .template : .original)
                    .resizable()
                    .frame(width: drawn.size.width * size, height: drawn.size.height * size)
            } else {
                Image(systemName: entry.core.item?.section.symbol ?? "circle")
                    .font(.system(size: 12 * size))
                    .saturation(monochrome ? 0 : 1)
                    .frame(width: side, height: side)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Content

    /// What each ear holds in the state shown, as the island itself would lay it out.
    private func entries(size: CGFloat, monochrome: Bool) -> (left: [Entry], right: [Entry]) {
        let layout = preferences.notchEars
        let side = NotchGeometry.featureIconSide(scale: size)
        let shown = layout.ears(available: preferences.availableNotchItems, open: open)
        // The readouts' room is what the icons in their ear leave, in the open state, as on the screen.
        let wide = layout.ears(available: preferences.availableNotchItems, open: true)
        let sharing = layout.ear(of: .system) == .left ? wide.left : wide.right
        let room = NotchGeometry.readoutRoom(sharing.map { NotchEarEntry(item: $0, width: $0 == .system ? 0 : side, isBars: $0 == .system) })
        let image = readouts(size: size, monochrome: monochrome, room: room)
        func make(_ items: [NotchItem], ear: NotchEar) -> [Entry] {
            let all = items.compactMap { item -> Entry? in
                guard item == .system else { return Entry(core: NotchEarEntry(item: item, width: side), image: nil) }
                if let image { return Entry(core: NotchEarEntry(item: item, width: image.size.width * size, isBars: true), image: image) }
                return open ? Entry(core: NotchEarEntry(item: item, width: side), image: nil) : nil
            }
            let fitted = NotchGeometry.fit(all.map(\.core), ear: ear)
            return all.filter { fitted.contains($0.core) }
        }
        return (make(shown.left, ear: .left), make(shown.right, ear: .right))
    }

    /// The readouts' bars in `room`, or nil when none are shown. `size` is their scale on the screen,
    /// which decides how many fit beside the notch.
    private func readouts(size: CGFloat, monochrome: Bool, room: CGFloat) -> NSImage? {
        let threshold = MenuBarPreview.hasBattery ? preferences.batteryMenuBarThreshold : BatteryMenuBar.off
        let readouts = MenuBarReadouts.make(
            from: MenuBarPreview.sample(batteryThreshold: threshold), metrics: preferences.menuBarMetrics, batteryThreshold: threshold
        )
        let style = preferences.menuBarStyle
        let widths = MenuBarImage.slotWidths(readouts, style: style).map { $0 * size }
        let shown = NotchGeometry.earReadouts(
            readouts.map(\.slot), hidden: Set(preferences.notchLeftHidden), limit: preferences.notchLeftCount,
            widths: widths, gap: MenuBarImage.readoutGap(for: style) * size, room: room
        ).map { readouts[$0] }
        guard !shown.isEmpty else { return nil }
        return MenuBarImage.make(shown, colored: preferences.coloredMenuBar, style: style, monochrome: monochrome)
    }

    /// The readouts' colours are resolved as they are drawn, which in a SwiftUI image would be in
    /// the settings window's look: dark bars on a black island. Drawn in the island's own look, they
    /// come out light on it, as on the screen.
    private static func drawn(_ image: NSImage, dark: Bool) -> NSImage {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return image }
        let drawn = NSImage(size: image.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance { image.draw(in: rect) }
            return true
        }
        drawn.isTemplate = image.isTemplate
        return drawn
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
