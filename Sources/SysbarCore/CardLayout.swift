/// How the popover arranges its cards, chosen in the settings.
public enum CardLayoutMode: String, CaseIterable, Sendable {
    /// Two columns for an even number of cards, one for an odd number, so the last card is never
    /// left alone beside an empty slot.
    case automatic
    /// A single column: a list of wide cards.
    case oneColumn
    /// Always two columns; an odd last card sits on its own.
    case twoColumns
}

public enum CardLayout {
    public static func columns(forCount count: Int, mode: CardLayoutMode = .automatic) -> Int {
        switch mode {
        case .automatic: count > 0 && count.isMultiple(of: 2) ? 2 : 1
        case .oneColumn: 1
        case .twoColumns: count > 1 ? 2 : 1
        }
    }
}
