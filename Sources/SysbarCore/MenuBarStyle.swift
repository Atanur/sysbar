/// What each menu bar slot shows, chosen in the settings.
public enum MenuBarStyle: String, CaseIterable, Sendable {
    /// A level bar and the reading next to it.
    case barsAndValues
    /// Level bars only: the smallest the menu bar item gets.
    case barsOnly
    /// The readings only, without bars.
    case valuesOnly

    public var showsBars: Bool { self != .valuesOnly }
    public var showsValues: Bool { self != .barsOnly }
}
