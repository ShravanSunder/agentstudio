import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@MainActor
@Suite("Tab reorder")
struct TabReorderTests {
    @Test
    func reorderTab_usesPreRemovalInsertionSlots() {
        struct ReorderCase {
            let name: String
            let movedTabOffset: Int
            let insertionIndex: Int
            let expectedOrder: [Int]
        }

        let cases = [
            ReorderCase(
                name: "leftward",
                movedTabOffset: 2,
                insertionIndex: 0,
                expectedOrder: [2, 0, 1, 3]
            ),
            ReorderCase(
                name: "rightward",
                movedTabOffset: 0,
                insertionIndex: 3,
                expectedOrder: [1, 2, 0, 3]
            ),
            ReorderCase(
                name: "final slot",
                movedTabOffset: 0,
                insertionIndex: 4,
                expectedOrder: [1, 2, 3, 0]
            ),
            ReorderCase(
                name: "no-op before tab",
                movedTabOffset: 1,
                insertionIndex: 1,
                expectedOrder: [0, 1, 2, 3]
            ),
            ReorderCase(
                name: "no-op after tab",
                movedTabOffset: 1,
                insertionIndex: 2,
                expectedOrder: [0, 1, 2, 3]
            ),
        ]

        for testCase in cases {
            let (tabLayout, tabs) = makeTabLayout()

            tabLayout.reorderTab(
                tabs[testCase.movedTabOffset].id,
                insertionIndex: testCase.insertionIndex
            )

            let expectedIds = testCase.expectedOrder.map { tabs[$0].id }
            #expect(tabLayout.tabs.map(\.id) == expectedIds, Comment(rawValue: testCase.name))
        }
    }

    @Test
    func reorderTab_preservesArrangementState() throws {
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

        tabLayout.reorderTab(thirdTab.id, insertionIndex: 0)

        #expect(tabLayout.tabs.map(\.id) == [thirdTab.id, firstTab.id, secondTab.id])
        #expect(try #require(tabLayout.tab(thirdTab.id)).allPaneIds == [thirdPaneId])
        #expect(try #require(tabLayout.tab(firstTab.id)).allPaneIds == [firstPaneId])
        #expect(try #require(tabLayout.tab(secondTab.id)).allPaneIds == [secondPaneId])
    }

    @Test
    func reorderTab_ignoresOutOfRangeInsertionIndex() {
        let firstTab = Tab(paneId: UUID(), name: "First")
        let secondTab = Tab(paneId: UUID(), name: "Second")
        let tabLayout = WorkspaceTabLayoutAtom()
        tabLayout.appendTab(firstTab)
        tabLayout.appendTab(secondTab)

        tabLayout.reorderTab(firstTab.id, insertionIndex: 3)

        #expect(tabLayout.tabs.map(\.id) == [firstTab.id, secondTab.id])
    }

    private func makeTabLayout() -> (WorkspaceTabLayoutAtom, [Tab]) {
        let tabs = [
            Tab(paneId: UUIDv7.generate(), name: "First"),
            Tab(paneId: UUIDv7.generate(), name: "Second"),
            Tab(paneId: UUIDv7.generate(), name: "Third"),
            Tab(paneId: UUIDv7.generate(), name: "Fourth"),
        ]
        let tabLayout = WorkspaceTabLayoutAtom()
        for tab in tabs {
            tabLayout.appendTab(tab)
        }
        return (tabLayout, tabs)
    }
}
