import XCTest

@testable import AgentStudio

final class TabArrangementTests: XCTestCase {

    // MARK: - Default Arrangement Invariants

    func test_init_singlePane_createsDefaultArrangement() {
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        XCTAssertEqual(tab.arrangements.count, 1)
        XCTAssertTrue(tab.arrangements[0].isDefault)
        XCTAssertEqual(tab.arrangements[0].name, "Default")
        XCTAssertEqual(tab.arrangements[0].layout.paneIds, [paneId])
        XCTAssertEqual(tab.arrangements[0].visiblePaneIds, [paneId])
    }

    func test_defaultArrangement_returnsIsDefaultTrue() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultLayout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let defaultArr = PaneArrangement(
            name: "Default", isDefault: true, layout: defaultLayout, visiblePaneIds: Set(defaultLayout.paneIds))
        let customArr = PaneArrangement(
            name: "Focus", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])

        let tab = Tab(
            panes: defaultLayout.paneIds,
            arrangements: [customArr, defaultArr],  // default not first in array
            activeArrangementId: customArr.id,
            activePaneId: paneA
        )

        // defaultArrangement should find the isDefault=true one regardless of position
        XCTAssertEqual(tab.defaultArrangement.id, defaultArr.id)
        XCTAssertTrue(tab.defaultArrangement.isDefault)
    }

    func test_activeArrangement_returnsSelectedArrangement() {
        let paneA = UUID()
        let paneB = UUID()
        let defaultLayout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: defaultLayout)
        let customArr = PaneArrangement(
            name: "Solo", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])

        let tab = Tab(
            panes: defaultLayout.paneIds,
            arrangements: [defaultArr, customArr],
            activeArrangementId: customArr.id,
            activePaneId: paneA
        )

        XCTAssertEqual(tab.activeArrangement.id, customArr.id)
        XCTAssertEqual(tab.activeArrangement.name, "Solo")
    }

    func test_activeArrangement_fallsBackToDefault_whenIdStale() {
        let paneId = UUID()
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneId))

        let tab = Tab(
            panes: [paneId],
            arrangements: [defaultArr],
            activeArrangementId: UUID(),  // stale — doesn't match any arrangement
            activePaneId: paneId
        )

        // Should fall back to default
        XCTAssertEqual(tab.activeArrangement.id, defaultArr.id)
    }

    // MARK: - Derived Properties Delegate to Active Arrangement

    func test_paneIds_comesFromActiveArrangement() {
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let fullLayout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .horizontal, position: .after)
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: fullLayout)
        let focusArr = PaneArrangement(
            name: "Focus", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])

        // Active is the focus arrangement
        let tab = Tab(
            panes: [paneA, paneB, paneC],
            arrangements: [defaultArr, focusArr],
            activeArrangementId: focusArr.id,
            activePaneId: paneA
        )

        XCTAssertEqual(tab.paneIds, [paneA])  // from focus arrangement
        XCTAssertFalse(tab.isSplit)
    }

    func test_isSplit_reflectsActiveArrangementLayout() {
        let paneA = UUID()
        let paneB = UUID()
        let splitLayout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: splitLayout)

        let tab = Tab(
            panes: [paneA, paneB],
            arrangements: [defaultArr],
            activeArrangementId: defaultArr.id,
            activePaneId: paneA
        )

        XCTAssertTrue(tab.isSplit)
    }

    func test_layout_returnsActiveArrangementLayout() {
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        XCTAssertEqual(tab.layout.paneIds, [paneId])
    }

    // MARK: - Arrangement Index Helpers

    func test_defaultArrangementIndex_findsCorrectIndex() {
        let paneA = UUID()
        let customArr = PaneArrangement(
            name: "Custom", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))

        let tab = Tab(
            panes: [paneA],
            arrangements: [customArr, defaultArr],  // default at index 1
            activeArrangementId: defaultArr.id,
            activePaneId: paneA
        )

        XCTAssertEqual(tab.defaultArrangementIndex, 1)
    }

    func test_activeArrangementIndex_findsCorrectIndex() {
        let paneA = UUID()
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))
        let customArr = PaneArrangement(
            name: "Custom", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])

        let tab = Tab(
            panes: [paneA],
            arrangements: [defaultArr, customArr],
            activeArrangementId: customArr.id,
            activePaneId: paneA
        )

        XCTAssertEqual(tab.activeArrangementIndex, 1)
    }

    func test_activeArrangementIndex_fallsBackToDefault_whenStale() {
        let paneA = UUID()
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))

        let tab = Tab(
            panes: [paneA],
            arrangements: [defaultArr],
            activeArrangementId: UUID(),  // stale
            activePaneId: paneA
        )

        XCTAssertEqual(tab.activeArrangementIndex, 0)  // falls back to default
    }

    // MARK: - Codable with Arrangements

    func test_codable_roundTrip_multipleArrangements() throws {
        let paneA = UUID()
        let paneB = UUID()
        let splitLayout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let defaultArr = PaneArrangement(name: "Default", isDefault: true, layout: splitLayout)
        let customArr = PaneArrangement(
            name: "Focus", isDefault: false, layout: Layout(paneId: paneA), visiblePaneIds: [paneA])

        let tab = Tab(
            panes: [paneA, paneB],
            arrangements: [defaultArr, customArr],
            activeArrangementId: customArr.id,
            activePaneId: paneA
        )

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        XCTAssertEqual(decoded.arrangements.count, 2)
        XCTAssertEqual(decoded.activeArrangementId, customArr.id)
        XCTAssertEqual(decoded.paneIds, [paneA])  // active arrangement is focus
        XCTAssertTrue(decoded.arrangements.contains { $0.isDefault })
        XCTAssertEqual(decoded.arrangements.first { !$0.isDefault }?.name, "Focus")
    }

    func test_codable_zoomedPaneId_isTransient() throws {
        let paneId = UUID()
        let tab = Tab(paneId: paneId)
        var mutableTab = tab
        mutableTab.zoomedPaneId = paneId

        let data = try JSONEncoder().encode(mutableTab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // zoomedPaneId is excluded from CodingKeys, should be nil after decode
        XCTAssertNil(decoded.zoomedPaneId)
    }

    // MARK: - PaneArrangement Model

    func test_paneArrangement_visiblePaneIds_defaultsToLayoutPanes() {
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        let arr = PaneArrangement(name: "Test", isDefault: false, layout: layout)

        XCTAssertEqual(arr.visiblePaneIds, Set(layout.paneIds))
    }

    func test_paneArrangement_visiblePaneIds_canBeSubset() {
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        let arr = PaneArrangement(
            name: "Subset",
            isDefault: false,
            layout: layout,
            visiblePaneIds: [paneA]
        )

        XCTAssertEqual(arr.visiblePaneIds, [paneA])
    }

    func test_paneArrangement_codable_roundTrip() throws {
        let paneA = UUID()
        let arr = PaneArrangement(
            name: "Focus",
            isDefault: false,
            layout: Layout(paneId: paneA),
            visiblePaneIds: [paneA]
        )

        let data = try JSONEncoder().encode(arr)
        let decoded = try JSONDecoder().decode(PaneArrangement.self, from: data)

        XCTAssertEqual(decoded.id, arr.id)
        XCTAssertEqual(decoded.name, "Focus")
        XCTAssertFalse(decoded.isDefault)
        XCTAssertEqual(decoded.visiblePaneIds, [paneA])
        XCTAssertEqual(decoded.layout.paneIds, [paneA])
    }
}
