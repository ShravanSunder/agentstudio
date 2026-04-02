import Foundation
import Testing

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
        let first = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: first.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        var paneIds = [first.id]
        for _ in 1..<count {
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
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

    func test_closeLastPane_removesTab() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(1)

        // Act
        store.removePaneFromLayout(paneIds[0], inTab: tab.id)

        // Assert
        #expect(store.tab(tab.id) == nil)
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

        let renderInfo = FlatTabStripMetrics.compute(
            layout: updated.layout,
            in: CGRect(x: 0, y: 0, width: 1200, height: 700),
            dividerThickness: AppStyle.paneGap,
            minimizedPaneIds: updated.minimizedPaneIds,
            collapsedPaneWidth: CollapsedPaneBar.barWidth
        )
        #expect(renderInfo.allMinimized)
        #expect(renderInfo.paneSegments.count == 3)
    }

    // MARK: - Minimize All Drawer Panes

    @Test

    func test_minimizeAllDrawerPanes_allInMinimizedSet() {
        // Arrange
        let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
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

        let renderInfo = FlatTabStripMetrics.compute(
            layout: drawer.layout,
            in: CGRect(x: 0, y: 0, width: 1200, height: 300),
            dividerThickness: AppStyle.paneGap,
            minimizedPaneIds: drawer.minimizedPaneIds,
            collapsedPaneWidth: CollapsedPaneBar.barWidth
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

        let renderInfo = FlatTabStripMetrics.compute(
            layout: updated.layout,
            in: CGRect(x: 0, y: 0, width: 1200, height: 700),
            dividerThickness: AppStyle.paneGap,
            minimizedPaneIds: updated.minimizedPaneIds,
            collapsedPaneWidth: CollapsedPaneBar.barWidth
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
        store.removePaneFromLayout(a, inTab: tab.id)

        // Assert: tab NOT empty, B and C remain minimized (no auto-expand)
        let updated = store.tab(tab.id)!
        #expect(updated.minimizedPaneIds.contains(b))
        #expect(updated.minimizedPaneIds.contains(c))
        #expect((updated.activePaneId) == nil)
    }

    // MARK: - Flat Strip Metrics Preserve Visible Dividers

    @Test

    func test_flatStripMetrics_minimize_preservesVisibleDividerAccounting() {
        let (tab, paneIds) = createTabWithPanes(3)
        let b = paneIds[1]

        store.minimizePane(b, inTab: tab.id)

        let updated = store.tab(tab.id)!
        let renderInfo = FlatTabStripMetrics.compute(
            layout: updated.layout,
            in: CGRect(x: 0, y: 0, width: 1200, height: 700),
            dividerThickness: AppStyle.paneGap,
            minimizedPaneIds: updated.minimizedPaneIds,
            collapsedPaneWidth: CollapsedPaneBar.barWidth
        )

        #expect(!(renderInfo.allMinimized))
        #expect(renderInfo.dividerSegments.isEmpty)
        #expect(renderInfo.paneSegments.filter(\.isMinimized).count == 1)
    }
}
