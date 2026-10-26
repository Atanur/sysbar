import Foundation
import Testing
@testable import SysbarCore

@Suite struct ArrangementTests {
    private typealias Metrics = Arrangement<MenuBarMetric>

    @Test func storedOrderIsCompletedWithNewCasesAndCleanedOfUnknownOnes() {
        let arrangement = Metrics(
            storedOrder: ["power", "bogus", "cpu", "power"], storedSelection: ["cpu", "power"],
            defaultSelection: MenuBarMetric.defaults, emptyMeansDefault: true
        )
        #expect(arrangement.order == [.power, .cpu, .gpu, .memory, .disk, .network])
        #expect(arrangement.selected == [.power, .cpu])
    }

    @Test func missingOrEmptySelectionFallsBackAsAsked() {
        let fresh = Metrics(storedOrder: nil, storedSelection: nil, defaultSelection: [.cpu], emptyMeansDefault: false)
        #expect(fresh.selected == [.cpu])
        let emptyMenuBar = Metrics(storedOrder: nil, storedSelection: [], defaultSelection: [.cpu], emptyMeansDefault: true)
        #expect(emptyMenuBar.selected == [.cpu])
        let noCards = Metrics(storedOrder: nil, storedSelection: [], defaultSelection: [.cpu], emptyMeansDefault: false)
        #expect(noCards.selected.isEmpty)
    }

    @Test func togglingKeepsTheUserOrderAndTheMinimum() {
        let arrangement = Metrics(order: [.network, .cpu], selected: [.cpu])
        #expect(arrangement.toggling(.network, minimum: 1).selected == [.network, .cpu])
        #expect(arrangement.toggling(.cpu, minimum: 1).selected == [.cpu])
        #expect(arrangement.toggling(.cpu, minimum: 0).selected.isEmpty)
    }

    @Test func movingTakesTheTargetsPlace() {
        let arrangement = Metrics(order: MenuBarMetric.allCases, selected: MenuBarMetric.allCases)
        #expect(arrangement.moving(.cpu, to: .memory).order == [.gpu, .memory, .cpu, .power, .disk, .network])
        #expect(arrangement.moving(.network, to: .gpu).order == [.cpu, .network, .gpu, .memory, .power, .disk])
        #expect(arrangement.moving(.cpu, to: .cpu) == arrangement)
    }

    @Test func steppingStopsAtTheEnds() {
        let arrangement = Metrics(order: MenuBarMetric.allCases, selected: [])
        #expect(arrangement.moving(.cpu, by: -1) == arrangement)
        #expect(arrangement.moving(.cpu, by: 1).order.prefix(2) == [.gpu, .cpu])
        #expect(arrangement.moving(.gpu, by: 99).order.last == .gpu)
    }

    @Test func storesOrderAndSelectionAsNames() {
        let arrangement = Metrics(order: [.memory, .cpu], selected: [.cpu, .memory])
        #expect(arrangement.storedSelection == ["memory", "cpu"])
        #expect(arrangement.storedOrder.prefix(2) == ["memory", "cpu"])
    }
}

@Suite struct ProjectLinksTests {
    @Test func bugReportFillsTheFormFields() throws {
        let url = ProjectLinks.bugReport(version: "0.1.1 (6)", system: "macOS 26.0", mac: "MacBook Pro · Apple M3 & co")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "github.com")
        #expect(url.path == "/Atanur/sysbar/issues/new")
        #expect(fields["template"] == "bug_report.yml")
        #expect(fields["version"] == "0.1.1 (6)")
        #expect(fields["mac"] == "MacBook Pro · Apple M3 & co")
    }

    @Test func releaseNotesPointAtTheRunningVersion() {
        #expect(ProjectLinks.changelog.absoluteString == "https://sysbar.atanur.dev/#changelog")
    }
}
