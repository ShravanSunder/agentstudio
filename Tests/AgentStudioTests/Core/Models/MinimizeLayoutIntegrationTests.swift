import Testing
import Foundation

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class MinimizeLayoutIntegrationTests {

    private var store: WorkspaceStore!

        init() {
        store = WorkspaceStore(
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            ))
    }

    // MARK: - Helpers

    private func createTabWithPanes(_ count: Int) -> (Tab, [UUID]) {
        let first = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: first.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        var paneIds = [first.id]
        for _ in 1..<count {
            let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
            store.insertPane(
                pane.id, inTab: tab.id, at: paneIds.last!,
                direction: .horizontal, position: .after
            )
            paneIds.append(pane.id)
        }
        return (store.tab(tab.id)!, paneIds)
    }

    // MARK: - Close Last Pane

    @Test

    func test_closeLastPane_tabSignalsEmpty() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(1)

        // Act
        let isEmpty = store.removePaneFromLayout(paneIds[0], inTab: tab.id)

        // Assert
        #expect(isEmpty)
    }

    // MARK: - Minimize All Tab Panes

    @Test

    func test_minimizeAllTabPanes_allInMinimizedSet() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(3)

        // Act
        for id in paneIds {
            let result = store.minimizePane(id, inTab: tab.id)
            #expect(result)
        }

        // Assert
        let updated = store.tab(tab.id)!
        #expect(updated.minimizedPaneIds == Set(paneIds))
        #expect((updated.activePaneId) == nil)

        let renderInfo = SplitRenderInfo.compute(
            layout: updated.layout,
            minimizedPaneIds: updated.minimizedPaneIds
        )
        #expect(renderInfo.allMinimized)
        #expect(renderInfo.allMinimizedPaneIds.count == 3)
    }

    // MARK: - Minimize All Drawer Panes

    @Test

    func test_minimizeAllDrawerPanes_allInMinimizedSet() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let d1 = store.addDrawerPane(to: pane.id)!
        let d2 = store.addDrawerPane(to: pane.id)!

        // Act
        let r1 = store.minimizeDrawerPane(d1.id, in: pane.id)
        let r2 = store.minimizeDrawerPane(d2.id, in: pane.id)

        // Assert
        #expect(r1)
        #expect(r2)
        let drawer = store.pane(pane.id)!.drawer!
        #expect(drawer.minimizedPaneIds == Set([d1.id, d2.id]))

        let renderInfo = SplitRenderInfo.compute(
            layout: drawer.layout,
            minimizedPaneIds: drawer.minimizedPaneIds
        )
        #expect(renderInfo.allMinimized)
    }

    // MARK: - Expand From All-Minimized

    @Test

    func test_expandFromAllMinimized_restoresPane() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(2)
        store.minimizePane(paneIds[0], inTab: tab.id)
        store.minimizePane(paneIds[1], inTab: tab.id)

        // Verify all minimized
        let beforeExpand = store.tab(tab.id)!
        #expect((beforeExpand.activePaneId) == nil)

        // Act
        store.expandPane(paneIds[0], inTab: tab.id)

        // Assert
        let updated = store.tab(tab.id)!
        #expect(!(updated.minimizedPaneIds.contains(paneIds[0])))
        #expect(updated.minimizedPaneIds.contains(paneIds[1]))
        #expect(updated.activePaneId == paneIds[0])

        let renderInfo = SplitRenderInfo.compute(
            layout: updated.layout,
            minimizedPaneIds: updated.minimizedPaneIds
        )
        #expect(!(renderInfo.allMinimized))
    }

    // MARK: - Close Pane Preserves Minimized State (No Auto-Expand)

    @Test

    func test_closePaneWithAllOthersMinimized_preservesMinimizedState() {
        // Arrange: 3 panes, minimize B and C, then close A
        let (tab, paneIds) = createTabWithPanes(3)
        let a = paneIds[0]
        let b = paneIds[1]
        let c = paneIds[2]
        store.minimizePane(b, inTab: tab.id)
        store.minimizePane(c, inTab: tab.id)

        // Verify A is active, B and C minimized
        let before = store.tab(tab.id)!
        #expect(before.activePaneId == a)

        // Act: close A — remaining panes (B, C) are both minimized
        let isEmpty = store.removePaneFromLayout(a, inTab: tab.id)

        // Assert: tab NOT empty, B and C remain minimized (no auto-expand)
        #expect(!(isEmpty))
        let updated = store.tab(tab.id)!
        #expect(updated.minimizedPaneIds.contains(b))
        #expect(updated.minimizedPaneIds.contains(c))
        #expect((updated.activePaneId) == nil)
    }

    // MARK: - SplitRenderInfo Nested Proportional Ratios

    @Test

    func test_splitRenderInfo_nestedMinimize_proportionalRatios() {
        // Arrange: 3 panes — A | (B | C), minimize B
        let (tab, paneIds) = createTabWithPanes(3)
        let b = paneIds[1]

        store.minimizePane(b, inTab: tab.id)

        // Act
        let updated = store.tab(tab.id)!
        let renderInfo = SplitRenderInfo.compute(
            layout: updated.layout,
            minimizedPaneIds: updated.minimizedPaneIds
        )

        // Assert: not all minimized, has split info entries
        #expect(!(renderInfo.allMinimized))
        #expect(!(renderInfo.splitInfo.isEmpty))

        // Find the inner split (B|C) — one side should be fully minimized
        let innerSplitInfo = renderInfo.splitInfo.values.first {
            $0.leftFullyMinimized || $0.rightFullyMinimized
        }
        #expect((innerSplitInfo) != nil)
        let minimizedCount =
            (innerSplitInfo?.leftMinimizedPaneIds.count ?? 0)
            + (innerSplitInfo?.rightMinimizedPaneIds.count ?? 0)
        #expect(minimizedCount == 1, "Exactly one pane should be in the minimized IDs")
    }
}
