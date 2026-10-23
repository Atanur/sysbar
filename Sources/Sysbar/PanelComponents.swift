import SwiftUI

/// A row of options drawn like the popover's tabs: the chosen one has a soft background that
/// slides to the next choice. A plain SwiftUI control, so it fades in with a panel without the
/// flashes an AppKit segmented control shows while animating.
struct CapsulePicker<Value: Hashable>: View {
    let options: [(title: String, value: Value)]
    /// The chosen option; nil when none is.
    let selected: Value?
    let onSelect: (Value) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                button(option.title, isSelected: option.value == selected) { onSelect(option.value) }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .opacity(isEnabled ? 1 : 0.5)
        .motion(.snappy(duration: 0.22), value: selected)
    }

    private func button(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    if isSelected {
                        Capsule().fill(Color.primary.opacity(0.12)).matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Why a panel's control does not work yet (the helper is not set up), with the button that fixes it.
struct HelperNote<Action: View>: View {
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            action.controlSize(.small)
        }
    }
}

// MARK: Motion

/// Animations here are small and run only when something changes. With "Reduce motion" on, the
/// change happens at once instead.
private struct MotionModifier<Trigger: Equatable>: ViewModifier {
    let animation: Animation
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: trigger)
    }
}

extension View {
    /// Animates changes of `value` with `animation`, unless the system asks for reduced motion.
    func motion<Trigger: Equatable>(_ animation: Animation = .snappy(duration: 0.2), value: Trigger) -> some View {
        modifier(MotionModifier(animation: animation, trigger: value))
    }

    /// A soft background while the pointer is over the view.
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }

    /// Draws the view in from the left once when it appears, like a graph being plotted.
    func revealOnAppear(duration: Double = 0.5) -> some View {
        modifier(RevealOnAppear(duration: duration))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            )
            .onHover { isHovering = $0 }
            .motion(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct RevealOnAppear: ViewModifier {
    let duration: Double
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().frame(width: revealed || reduceMotion ? geometry.size.width : 0)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: duration)) { revealed = true }
            }
    }
}

/// A button that gives a little under the finger: shrinks slightly while pressed.
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
