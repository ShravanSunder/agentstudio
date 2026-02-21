import Testing
import Foundation

@testable import AgentStudio

@Suite(.serialized)
final class TabTests {

    // MARK: - Init

    @Test

    func test_init_singlePane() {
        // Arrange
        let paneId = UUID()

        // Act
        let tab = Tab(paneId: paneId)

        // Assert
        #expect(tab.paneIds == [paneId])
        #expect(tab.activePaneId == paneId)
        #expect(!(tab.isSplit))
    }

    @Test

    func test_init_customId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()

        // Act
        let tab = Tab(id: tabId, paneId: paneId)

        // Assert
        #expect(tab.id == tabId)
    }

    @Test

    func test_init_withLayout() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let arrangement = PaneArrangement(
            name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(
            panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA
        )

        // Assert
        #expect(tab.paneIds == [paneA, paneB])
        #expect(tab.activePaneId == paneA)
        #expect(tab.isSplit)
    }

    // MARK: - Derived Properties

    @Test

    func test_paneIds_matchesLayout() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let paneC = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
            .inserting(paneId: paneC, at: paneB, direction: .vertical, position: .after)

        // Act
        let arrangement = PaneArrangement(
            name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(
            panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA
        )

        // Assert
        #expect(tab.paneIds == [paneA, paneB, paneC])
    }

    @Test

    func test_isSplit_singlePane_false() {
        // Arrange
        let tab = Tab(paneId: UUID())

        // Assert
        #expect(!(tab.isSplit))
    }

    @Test

    func test_isSplit_multiplePanes_true() {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)

        // Act
        let arrangement = PaneArrangement(
            name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(
            panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneA
        )

        // Assert
        #expect(tab.isSplit)
    }

    // MARK: - Codable Round-Trip

    @Test

    func test_codable_singlePane_roundTrips() throws {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        #expect(decoded.id == tab.id)
        #expect(decoded.paneIds == [paneId])
        #expect(decoded.activePaneId == paneId)
    }

    @Test

    func test_codable_splitLayout_roundTrips() throws {
        // Arrange
        let paneA = UUID()
        let paneB = UUID()
        let layout = Layout(paneId: paneA)
            .inserting(paneId: paneB, at: paneA, direction: .horizontal, position: .after)
        let arrangement = PaneArrangement(
            name: "Default", isDefault: true, layout: layout, visiblePaneIds: Set(layout.paneIds))
        let tab = Tab(
            panes: layout.paneIds, arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: paneB
        )

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        #expect(decoded.id == tab.id)
        #expect(decoded.paneIds == [paneA, paneB])
        #expect(decoded.activePaneId == paneB)
        #expect(decoded.isSplit)
    }

    @Test

    func test_codable_nilActivePane_roundTrips() throws {
        // Arrange
        let layout = Layout()
        let arrangement = PaneArrangement(name: "Default", isDefault: true, layout: layout, visiblePaneIds: [])
        let tab = Tab(panes: [], arrangements: [arrangement], activeArrangementId: arrangement.id, activePaneId: nil)

        // Act
        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(Tab.self, from: data)

        // Assert
        #expect((decoded.activePaneId) == nil)
    }

    // MARK: - Hashable

    @Test

    func test_hashable_sameId_sameHash() {
        // Arrange — two tabs with same id but independent arrangements
        let tabId = UUID()
        let paneId = UUID()
        let tab1 = Tab(id: tabId, paneId: paneId)
        let tab2 = Tab(id: tabId, paneId: paneId)

        // Assert — hash is identity-based, equality is memberwise
        #expect(tab1.hashValue == tab2.hashValue)
        // Different arrangement UUIDs means they are NOT equal under memberwise equality
        #expect(tab1 != tab2)
    }

    @Test

    func test_equality_sameInstance_isEqual() {
        // Arrange — exact same tab instance
        let tab = Tab(id: UUID(), paneId: UUID())

        // Assert
        #expect(tab == tab)
    }
}
