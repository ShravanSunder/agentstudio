import XCTest
@testable import AgentStudio

final class TabTests: XCTestCase {

    // MARK: - Init

    func test_init_singlePane() {
        // Arrange
        let paneId = UUID()

        // Act
        let tab = Tab(paneId: paneId)

        // Assert
        XCTAssertEqual(tab.paneIds, [paneId])
        XCTAssertEqual(tab.activePaneId, paneId)
        XCTAssertFalse(tab.isSplit)
    }

    func test_init_customId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()

        // Act
        let tab = Tab(id: tabId, paneId: paneId)

        // Assert
        XCTAssertEqual(tab.id, tabId)
    }

    func test_init_withLayout() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA)

        // Assert
        XCTAssertEqual(tab.paneIds, [paneA, paneB])
        XCTAssertEqual(tab.activePaneId, paneA)
        XCTAssertTrue(tab.isSplit)
    }

    // MARK: - Derived Properties

    func test_paneIds_matchesLayout() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        // Act
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA)

        // Assert
        XCTAssertEqual(tab.paneIds, [paneA, paneB, paneC])
    }

    func test_isSplit_singlePane_false() {
        // Arrange
        let tab = Tab(paneId: UUID())

        // Assert
        XCTAssertFalse(tab.isSplit)
    }

    func test_isSplit_multiplePanes_true() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA)

        // Assert
        XCTAssertTrue(tab.isSplit)
    }

    // MARK: - Codable Round-Trip

    func test_codable_singlePane_roundTrips() throws {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, tab.id)
        XCTAssertEqual(decoded.paneIds, [paneId])
        XCTAssertEqual(decoded.activePaneId, paneId)
    }

    func test_codable_splitLayout_roundTrips() throws {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneB)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertEqual(decoded.id, tab.id)
        XCTAssertEqual(decoded.paneIds, [paneA, paneB])
        XCTAssertEqual(decoded.activePaneId, paneB)
        XCTAssertTrue(decoded.isSplit)
    }

    func test_codable_nilActivePane_roundTrips() throws {
        // Arrange
        let layout = Layout()
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: [])
        let tab = Tab(panes: [], arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: nil)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        XCTAssertNil(decoded.activePaneId)
    }

    // MARK: - Hashable

    func test_hashable_sameId_sameHash() {
        // Arrange — two tabs with same id but independent arrangements
        let tabId = UUID()
        let paneId = UUID()
        let tab1 = Tab(id: tabId, paneId: paneId)
        let tab2 = Tab(id: tabId, paneId: paneId)

        // Assert — hash is identity-based, equality is memberwise
        XCTAssertEqual(tab1.hashValue, tab2.hashValue)
        // Different arrangement UUIDs means they are NOT equal under memberwise equality
        XCTAssertNotEqual(tab1, tab2)
    }

    func test_equality_sameInstance_isEqual() {
        // Arrange — exact same tab instance
        let tab = Tab(id: UUID(), paneId: UUID())

        // Assert
        XCTAssertEqual(tab, tab)
    }
}
