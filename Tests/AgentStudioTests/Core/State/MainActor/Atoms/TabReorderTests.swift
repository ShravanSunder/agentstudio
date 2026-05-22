import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Tab reorder")
struct TabReorderTests {
    @Test
    func reorderTab_movesTabToAbsoluteIndexAndKeepsArrangementState() throws {
        let firstPaneId = UUID()
        let secondPaneId = UUID()
        let thirdPaneId = UUID()
        let firstTab = Tab(paneId: firstPaneId, name: "First")
        let secondTab = Tab(paneId: secondPaneId, name: "Second")
        let thirdTab = Tab(paneId: thirdPaneId, name: "Third")
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(firstTab)
        tabLayout.appendTab(secondTab)
        tabLayout.appendTab(thirdTab)

        tabLayout.reorderTab(thirdTab.id, to: 0)

        #expect(tabLayout.tabs.map(\.id) == [thirdTab.id, firstTab.id, secondTab.id])
        #expect(try #require(tabLayout.tab(thirdTab.id)).allPaneIds == [thirdPaneId])
        #expect(try #require(tabLayout.tab(firstTab.id)).allPaneIds == [firstPaneId])
        #expect(try #require(tabLayout.tab(secondTab.id)).allPaneIds == [secondPaneId])
    }

    @Test
    func reorderTab_ignoresOutOfRangeIndex() {
        let firstTab = Tab(paneId: UUID(), name: "First")
        let secondTab = Tab(paneId: UUID(), name: "Second")
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(firstTab)
        tabLayout.appendTab(secondTab)

        tabLayout.reorderTab(firstTab.id, to: 2)

        #expect(tabLayout.tabs.map(\.id) == [firstTab.id, secondTab.id])
    }
}
