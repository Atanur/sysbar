import AppKit
import SysbarCore
import SwiftUI

/// How the island at the top of the screen looks and behaves: which displays show it, what fills it,
/// which items are in its two ears and when they show, how its icons look and what opens it.
struct NotchSettingsPage: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        SettingsPageScaffold(page: .notch) {
            SettingsGroup(title: L("Preview"), footer: previewFooter) { NotchPreview(preferences: preferences) }

            SettingsGroup(title: L("Displays"), footer: L("A display without a notch gets a capsule at the top centre. With all displays, each has its own island, and opening one leaves the others closed.")) {
                SettingsRow(symbol: "display.2", title: L("Show on")) {
                    menu(L("Show on"), $preferences.notchDisplays) { $0.title }
                }
            }

            SettingsGroup(title: L("Background"), footer: L("Black merges with the notch; automatic uses glass on a display without one. A transparent island has no fill, so its text gets a faint shadow. Glass and transparent follow the system's light or dark look.")) {
                SettingsRow(symbol: "circle.lefthalf.filled", title: L("Background")) {
                    menu(L("Background"), $preferences.notchBackground) { $0.title }
                }
            }

            SettingsGroup(
                title: NotchEar.left.title,
                footer: L("Drag a row to put it in another place or on the other side, or use its menu. An item that shows only when open is not on the closed island; it appears in its place when the island opens.")
            ) { NotchEarRows(preferences: preferences, ear: .left) }

            SettingsGroup(
                title: NotchEar.right.title,
                footer: L("Every item is also a tab of the open island, so none can be hidden for good. To remove a feature, turn it off on its own page. While the heat warning is on, or the Mac is kept awake, a glyph for it shows here too.")
            ) { NotchEarRows(preferences: preferences, ear: .right) }

            SettingsGroup(title: L("System readouts"), footer: L("The readouts come from the Readouts page. Only as many as fit beside the notch, with the other items in the same ear, are shown; the rest are in the open panel.")) {
                SettingsRow(symbol: "number", title: L("Readouts shown")) {
                    Picker(L("Readouts shown"), selection: $preferences.notchLeftCount) {
                        ForEach(Preferences.earCountRange, id: \.self) {
                            Text($0 == 0 ? L("None") : "\($0)").tag($0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                ForEach(Self.earSlots(preferences), id: \.id) { slot in
                    RowDivider()
                    SettingsRow(symbol: slot.symbol, title: slot.title) {
                        RowToggle(isOn: Binding(
                            get: { !preferences.notchLeftHidden.contains(slot.id) },
                            set: { _ in preferences.notchLeftHidden = Preferences.toggled(slot.id, in: preferences.notchLeftHidden) }
                        ))
                    }
                    .disabled(preferences.notchLeftCount == 0)
                }
            }

            SettingsGroup(title: L("Icons"), footer: L("Monochrome draws the readouts and icons in one colour; the heat warning keeps its own. On a display without a notch, large is limited to what fits the menu bar's height.")) {
                SettingsRow(symbol: "paintpalette", title: L("Icon colors")) {
                    segmented(L("Icon colors"), $preferences.notchIconStyle) { $0.title }
                }
                RowDivider()
                SettingsRow(symbol: "textformat.size", title: L("Icon size")) {
                    segmented(L("Icon size"), $preferences.notchIconSize) { $0.title }
                }
            }

            SettingsGroup(title: L("Visibility"), footer: L("In full screen, the island hides until the pointer reaches it.")) {
                SettingsRow(symbol: "eye", title: L("Show the island")) {
                    menu(L("Show the island"), $preferences.notchVisibility) { $0.title }
                }
            }

            SettingsGroup(title: L("Opening"), footer: L("With click, resting the pointer on the island does nothing; a click, or a feature's icon, opens it.")) {
                SettingsRow(symbol: "cursorarrow.rays", title: L("Open on")) {
                    segmented(L("Open on"), $preferences.notchOpening) { $0.title }
                }
            }
        }
    }

    private var previewFooter: String? {
        preferences.sysbarPlacement == .notch ? nil : L("Takes effect once Sysbar is shown at the top of the screen, under Appearance.")
    }

    /// What the left ear can show: the readouts the menu bar has, the battery among them.
    private static func earSlots(_ preferences: Preferences) -> [EarSlot] {
        var slots = preferences.menuBarMetrics.map { EarSlot(id: $0.rawValue, title: $0.title, symbol: $0.symbol) }
        if MenuBarPreview.hasBattery, preferences.batteryMenuBarThreshold != BatteryMenuBar.off {
            slots.append(EarSlot(id: MenuBarSlot.battery.id, title: L("Battery"), symbol: "battery.50"))
        }
        return slots
    }

    private func menu<Value: Hashable & CaseIterable>(
        _ title: String, _ selection: Binding<Value>, label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func segmented<Value: Hashable & CaseIterable>(
        _ title: String, _ selection: Binding<Value>, label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        Picker(title, selection: selection) {
            ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private struct EarSlot {
        let id: String
        let title: String
        let symbol: String
    }
}

/// The island as it will look, drawn from fixed sample values on a mock desktop; closed, or open
/// with the items that show only then, and the panel hanging from the strip in one outline with it.
private struct NotchPreview: View {
    @ObservedObject var preferences: Preferences
    @State private var open = false
    /// The strip's width as laid out, which the open outline is drawn around.
    @State private var stripWidth: CGFloat = 0

    private static let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    private static let height: CGFloat = 38
    /// The island drawn larger than life, so its readouts and icons can be made out.
    private static let zoom: CGFloat = 1.6
    /// The sample panel under the strip: how much wider than it and how tall.
    private static let panelWidthRatio: CGFloat = 1.3
    private static let panelHeight: CGFloat = 76

    private struct StripWidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    /// The strip with the panel under it as one outline, the same the island draws.
    private struct PopupShape: Shape {
        let shape: NotchGeometry.Shape
        let stripWidth: CGFloat
        let header: CGFloat
        let bottomCorner: CGFloat

        func path(in rect: CGRect) -> Path {
            let left = (rect.width - stripWidth) / 2
            return Path(IslandOutline.popup(
                size: rect.size, shape: shape, strip: left...(left + stripWidth), header: header, bottomCorner: bottomCorner
            ))
        }
    }

    /// An item in an ear, with the readouts' image when it is the System item with bars to show.
    private struct Entry {
        let core: NotchEarEntry
        let image: NSImage?
    }

    var body: some View {
        let shape: NotchGeometry.Shape = Self.hasNotch ? .notch : .capsule
        let fill = preferences.notchBackground.fill(for: shape)
        let size = NotchGeometry.contentScale(preferences.notchIconSize, rowHeight: Self.height)
        let monochrome = preferences.notchIconStyle == .monochrome
        let ears = entries(size: size, monochrome: monochrome)
        let titles = { (entries: [Entry]) in entries.compactMap { $0.core.item?.section.title }.joined(separator: ", ") }
        return VStack(spacing: 6) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .leading, endPoint: .trailing)
                    .opacity(0.8)
                island(fill: fill, shape: shape, size: size, monochrome: monochrome, ears: ears)
            }
            .frame(height: Self.height * Self.zoom + 44 + (open ? Self.panelHeight : 0))
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

    @ViewBuilder
    private func island(
        fill: NotchBackground.Fill, shape: NotchGeometry.Shape, size: CGFloat, monochrome: Bool,
        ears: (left: [Entry], right: [Entry])
    ) -> some View {
        // Every length is multiplied out rather than the island scaled up, so the drawings stay sharp.
        let zoom = Self.zoom
        let scale = size * zoom
        let dark = fill.isDark || NSApp.effectiveAppearance.isDark
        let strip = HStack(spacing: 0) {
            ear(ears.left, scale: scale, monochrome: monochrome, dark: dark).frame(minWidth: 0, alignment: .trailing)
            if shape == .notch {
                // The notch itself: black whatever fills the island.
                UnevenRoundedRectangle(bottomLeadingRadius: 8 * zoom, bottomTrailingRadius: 8 * zoom, style: .continuous)
                    .fill(.black).frame(width: 70 * zoom)
            } else {
                Spacer().frame(width: NotchGeometry.capsuleGap * zoom)
            }
            ear(ears.right, scale: scale, monochrome: monochrome, dark: dark)
        }
        .foregroundStyle(.primary)
        .shadow(color: fill == .clear ? .black.opacity(0.5) : .clear, radius: 2)
        .padding(.horizontal, 14 * zoom)
        .frame(height: Self.height * zoom)
        .background {
            GeometryReader { Color.clear.preference(key: StripWidthKey.self, value: $0.size.width) }
        }
        VStack(spacing: 0) {
            strip
            if open { samplePanel }
        }
        .onPreferenceChange(StripWidthKey.self) { stripWidth = $0 }
        .background { background(fill: fill, shape: shape) }
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Cards standing for the panel's content, in the panel that hangs from the strip.
    private var samplePanel: some View {
        HStack(spacing: 6 * Self.zoom) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: MetricCardStyle.corner * Self.zoom / 2, style: .continuous)
                    .fill(.primary.opacity(0.12))
            }
        }
        .padding(.horizontal, 10 * Self.zoom)
        .padding(.top, 4 * Self.zoom)
        .padding(.bottom, 10 * Self.zoom)
        .frame(width: stripWidth * Self.panelWidthRatio, height: Self.panelHeight)
    }

    /// One ear's items in order, with the gaps the island keeps between them.
    private func ear(_ entries: [Entry], scale: CGFloat, monochrome: Bool, dark: Bool) -> some View {
        let side = NotchGeometry.featureIconSide(scale: scale)
        return HStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.core.slot) { index, entry in
                let gap = index + 1 < entries.count ? NotchGeometry.earGap(entry.core, entries[index + 1].core) * Self.zoom : 0
                Group {
                    if let image = entry.image {
                        let drawn = Self.drawn(image, dark: dark)
                        Image(nsImage: drawn)
                            .renderingMode(drawn.isTemplate ? .template : .original)
                            .resizable()
                            .frame(width: drawn.size.width * scale, height: drawn.size.height * scale)
                    } else {
                        Image(systemName: entry.core.item?.section.symbol ?? "circle")
                            .font(.system(size: 12 * scale))
                            .saturation(monochrome ? 0 : 1)
                            .frame(width: side, height: side)
                    }
                }
                .padding(.trailing, gap)
            }
        }
    }

    private func background(fill: NotchBackground.Fill, shape: NotchGeometry.Shape) -> some View {
        let corner = 14 * Self.zoom
        let closed = UnevenRoundedRectangle(
            topLeadingRadius: shape == .notch ? 0 : corner, bottomLeadingRadius: corner,
            bottomTrailingRadius: corner, topTrailingRadius: shape == .notch ? 0 : corner,
            style: .continuous
        )
        let popup = PopupShape(
            shape: shape, stripWidth: stripWidth, header: Self.height * Self.zoom, bottomCorner: 2 * corner
        )
        return Group {
            switch fill {
            case .black: if open { popup.fill(.black) } else { closed.fill(.black) }
            case .glass: if open { popup.fill(.ultraThinMaterial) } else { closed.fill(.ultraThinMaterial) }
            case .clear: Color.clear
            }
        }
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

extension NotchDisplayChoice {
    var title: String {
        switch self {
        case .builtIn: L("Built-in display only")
        case .all: L("All displays")
        case .active: L("Display with the active menu bar")
        }
    }
}

extension NotchBackground {
    var title: String {
        switch self {
        case .automatic: L("Automatic")
        case .black: L("Black")
        case .glass: L("Glass")
        case .transparent: L("Transparent")
        }
    }
}

extension NotchIconStyle {
    var title: String {
        switch self {
        case .colored: L("Colored")
        case .monochrome: L("Monochrome")
        }
    }
}

extension NotchIconSize {
    var title: String {
        switch self {
        case .small: L("Small")
        case .medium: L("Medium")
        case .large: L("Large")
        }
    }
}

extension NotchIslandVisibility {
    var title: String {
        switch self {
        case .always: L("Always")
        case .pointer: L("Only when the pointer is on it")
        }
    }
}

extension NotchOpening {
    var title: String {
        switch self {
        case .hover: L("Hover")
        case .click: L("Click")
        }
    }
}
