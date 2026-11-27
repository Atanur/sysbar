import AppKit
import SwiftUI
import SysbarCore

/// One feature icon of the island: the tab it opens and what its icon shows.
struct NotchFeature: Equatable {
    enum Kind: Equatable {
        case stash(items: Int)
        case clipboard
    }

    let section: PopoverSection
    let kind: Kind
    var item: NotchItem { section.notchItem }
    /// The state in words, for the tooltip and for VoiceOver; empty when there is none.
    let value: String
}

extension PopoverSection {
    /// The item this tab is in the island's ears.
    nonisolated var notchItem: NotchItem {
        switch self {
        case .system: .system
        case .stash: .stash
        case .clipboard: .clipboard
        }
    }

    /// The tabs that have an icon of their own in an ear; the System tab has the readouts.
    static let notchFeatures: [PopoverSection] = [.stash, .clipboard]
}

extension NotchItem {
    /// The tab the item opens.
    var section: PopoverSection {
        switch self {
        case .system: .system
        case .stash: .stash
        case .clipboard: .clipboard
        }
    }
}

extension NotchStatus {
    /// The panel of the System page the glyph unfolds.
    var panel: PopoverPanel { self == .heat ? .thermal : .keepAwake }
}

/// A status glyph of the closed island's right ear: what it shows, and the words for the tooltip and VoiceOver.
struct NotchStatusInfo: Equatable {
    let status: NotchStatus
    /// The warning level, for the heat glyph.
    var heat: LoadLevel?
    /// The panel the glyph opens, named for VoiceOver and the tooltip.
    let title: String
    let value: String
}

/// What the ears show and do: the features on offer, the status glyphs, the tab the open island is on, and the click.
@MainActor
final class NotchFeatureModel: ObservableObject {
    /// The features that are on, whichever ear they are in and whether or not they show while closed.
    @Published var features: [NotchFeature] = []
    /// The signals that apply now, which the closed island shows in its right ear.
    @Published var statuses: [NotchStatusInfo] = []
    /// The tab the open island shows, marked on its item.
    @Published var active: PopoverSection?
    var onSelect: (PopoverSection) -> Void = { _ in }
    var onStatus: (NotchStatus) -> Void = { _ in }
}

/// How one ear item is drawn; a change redraws it.
struct NotchItemStyle: Equatable {
    var slot: NotchSlot
    /// The readouts' image for the System item, if it has readouts to show; without, it is an icon.
    var readouts: NSImage?
    /// The icons' size relative to the default.
    var scale: CGFloat = 1
    /// One ink for every icon, apart from the heat warning, which keeps its colour.
    var monochrome = false
    /// The island is open: the System item is then a tab, and not the island's one button.
    var open = false
    /// What the readouts say, for VoiceOver.
    var summary = ""
    /// The layout item, nil for a status glyph.
    var item: NotchItem? { if case .item(let item) = slot { item } else { nil } }
}

/// One item of an ear: the readouts' bars, a feature's icon drawn with the same symbols as the
/// tabs, or a status glyph. Clicking an item opens the island on its tab, or closes it when that tab is
/// already open; a glyph opens the System page with its panel unfolded.
struct NotchItemView: View {
    @ObservedObject var model: NotchFeatureModel
    let style: NotchItemStyle

    private var side: CGFloat { NotchGeometry.featureIconSide(scale: style.scale) }
    private var section: PopoverSection { style.item?.section ?? .system }
    private var feature: NotchFeature? { model.features.first { $0.section == section } }
    private var statusInfo: NotchStatusInfo? {
        guard case .status(let status) = style.slot else { return nil }
        return model.statuses.first { $0.status == status }
    }

    var body: some View {
        if case .status(let status) = style.slot {
            statusButton(status)
        } else {
            itemButton
        }
    }

    private var itemButton: some View {
        let isActive = model.active == section
        return Button { model.onSelect(section) } label: { label(isActive: isActive) }
            .buttonStyle(PressScaleButtonStyle(scale: 0.9))
            .help([title, value].filter { !$0.isEmpty }.joined(separator: " · "))
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// A glyph in the heat's colour or the accent's, one ink with the icons otherwise.
    private func statusButton(_ status: NotchStatus) -> some View {
        let info = statusInfo
        return Button { model.onStatus(status) } label: {
            statusGlyph(status, heat: info?.heat)
                .scaleEffect(style.scale)
                .frame(width: side, height: side)
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.9))
        .help([info?.title, info?.value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityLabel(info?.title ?? "")
        .accessibilityValue(info?.value ?? "")
        .accessibilityHint(L("Opens the System page"))
    }

    @ViewBuilder
    private func statusGlyph(_ status: NotchStatus, heat: LoadLevel?) -> some View {
        switch status {
        case .heat:
            Image(systemName: "thermometer.high")
                .font(.callout)
                .foregroundStyle(heat?.color ?? LoadLevel.high.color)
        case .keepAwake:
            KeepAwakeIcon(isKeptAwake: true)
                .foregroundStyle(style.monochrome ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
        }
    }

    /// Closed, the readouts are the one button for the island; open, the button for the System tab.
    private var title: String {
        style.item == .system && !style.open ? "Sysbar" : section.title
    }

    private var value: String { style.item == .system ? style.summary : feature?.value ?? "" }

    @ViewBuilder
    private func label(isActive: Bool) -> some View {
        let fill = Color.white.opacity(isActive ? 0.22 : 0)
        if style.item == .system, let image = style.readouts {
            // The capsule reaches past the bars into the gap beside them.
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .frame(width: image.size.width * style.scale, height: image.size.height * style.scale)
                .foregroundStyle(.primary)
                .padding(.horizontal, NotchGeometry.highlightPadding)
                .frame(height: max(side, image.size.height * style.scale))
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        } else {
            icon
                .frame(width: side, height: side)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
    }

    /// The icon at the chosen size, in one ink.
    private var icon: some View {
        Image(systemName: section.symbol).font(.callout).foregroundStyle(.primary)
            .scaleEffect(style.scale)
            .saturation(style.monochrome ? 0 : 1)
    }
}

/// Takes the click that brings the island forward, as the panel does not become active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
