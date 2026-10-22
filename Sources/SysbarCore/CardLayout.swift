/// How many columns the popover's cards use. An even number of cards sits in two columns; an odd
/// number stacks in one, so the last card is never left alone beside an empty slot.
public enum CardLayout {
    public static func columns(forCount count: Int) -> Int {
        count > 0 && count.isMultiple(of: 2) ? 2 : 1
    }
}
