import Testing
@testable import SysbarCore

@Suite struct MenuBarStyleTests {
    @Test func eachStyleShowsWhatItsNameSays() {
        #expect(MenuBarStyle.barsAndValues.showsBars && MenuBarStyle.barsAndValues.showsValues)
        #expect(MenuBarStyle.barsOnly.showsBars && !MenuBarStyle.barsOnly.showsValues)
        #expect(!MenuBarStyle.valuesOnly.showsBars && MenuBarStyle.valuesOnly.showsValues)
    }

    @Test func aStoredNameIsReadBack() {
        for style in MenuBarStyle.allCases {
            #expect(MenuBarStyle(rawValue: style.rawValue) == style)
        }
        #expect(MenuBarStyle(rawValue: "nonsense") == nil)
    }
}
