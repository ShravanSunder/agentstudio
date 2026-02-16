import XCTest
@testable import AgentStudio

@MainActor
final class MinimizeLayoutIntegrationTests: XCTestCase {

    private var store: WorkspaceStore!

    override func setUp() {
        super.setUp()
        store = WorkspaceStore(persistor: WorkspacePersistor(
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

    func test_closeLastPane_tabSignalsEmpty() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(1)

        // Act
        let isEmpty = store.removePaneFromLayout(paneIds[0], inTab: tab.id)

        // Assert
        XCTAssertTrue(isEmpty, "Removing the last pane should signal tab empty")
    }

    // MARK: - Minimize All Tab Panes

    func test_minimizeAllTabPanes_allInMinimizedSet() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(3)

        // Act
        for id in paneIds {
            let result = store.minimizePane(id, inTab: tab.id)
            XCTAssertTrue(result, "Minimizing pane \(id) should succeed")
        }

        // Assert
        let updated = store.tab(tab.id)!
        XCTAssertEqual(updated.minimizedPaneIds, Set(paneIds))
        XCTAssertNil(updated.activePaneId, "No active pane when all minimized")

        let renderInfo = SplitRenderInfo.compute(
            layout: updated.layout,
            minimizedPaneIds: updated.minimizedPaneIds
        )
        XCTAssertTrue(renderInfo.allMinimized)
        XCTAssertEqual(renderInfo.allMinimizedPaneIds.count, 3)
    }

    // MARK: - Minimize All Drawer Panes

    func test_minimizeAllDrawerPanes_allInMinimizedSet() {
        // Arrange
        let pane = store.createPane(source: .floating(workingDirectory: nil, title: nil))
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let d1 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "D1")
        )!
        let d2 = store.addDrawerPane(
            to: pane.id,
            content: .terminal(TerminalState(provider: .ghostty, lifetime: .temporary)),
            metadata: PaneMetadata(source: .floating(workingDirectory: nil, title: nil), title: "D2")
        )!

        // Act
        let r1 = store.minimizeDrawerPane(d1.id, in: pane.id)
        let r2 = store.minimizeDrawerPane(d2.id, in: pane.id)

        // Assert
        XCTAssertTrue(r1)
        XCTAssertTrue(r2)
        let drawer = store.pane(pane.id)!.drawer!
        XCTAssertEqual(drawer.minimizedPaneIds, Set([d1.id, d2.id]))

        let renderInfo = SplitRenderInfo.compute(
            layout: drawer.layout,
            minimizedPaneIds: drawer.minimizedPaneIds
        )
        XCTAssertTrue(renderInfo.allMinimized)
    }

    // MARK: - Expand From All-Minimized

    func test_expandFromAllMinimized_restoresPane() {
        // Arrange
        let (tab, paneIds) = createTabWithPanes(2)
        store.minimizePane(paneIds[0], inTab: tab.id)
        store.minimizePane(paneIds[1], inTab: tab.id)

        // Verify all minimized
        let beforeExpand = store.tab(tab.id)!
        XCTAssertNil(beforeExpand.activePaneId)

        // Act
        store.expandPane(paneIds[0], inTab: tab.id)

        // Assert
        let updated = store.tab(tab.id)!
        XCTAssertFalse(updated.minimizedPaneIds.contains(paneIds[0]))
        XCTAssertTrue(updated.minimizedPaneIds.contains(paneIds[1]))
        XCTAssertEqual(updated.activePaneId, paneIds[0])

        let renderInfo = SplitRenderInfo.compute(
            layout: updated.layout,
            minimizedPaneIds: updated.minimizedPaneIds
        )
        XCTAssertFalse(renderInfo.allMinimized)
    }

    // MARK: - Close Pane Preserves Minimized State (No Auto-Expand)

    func test_closePaneWithAllOthersMinimized_preservesMinimizedState() {
        // Arrange: 3 panes, minimize B and C, then close A
        let (tab, paneIds) = createTabWithPanes(3)
        let a = paneIds[0], b = paneIds[1], c = paneIds[2]
        store.minimizePane(b, inTab: tab.id)
        store.minimizePane(c, inTab: tab.id)

        // Verify A is active, B and C minimized
        let before = store.tab(tab.id)!
        XCTAssertEqual(before.activePaneId, a)

        // Act: close A — remaining panes (B, C) are both minimized
        let isEmpty = store.removePaneFromLayout(a, inTab: tab.id)

        // Assert: tab NOT empty, B and C remain minimized (no auto-expand)
        XCTAssertFalse(isEmpty)
        let updated = store.tab(tab.id)!
        XCTAssertTrue(updated.minimizedPaneIds.contains(b))
        XCTAssertTrue(updated.minimizedPaneIds.contains(c))
        XCTAssertNil(updated.activePaneId, "No auto-expand when all remaining panes are minimized")
    }

    // MARK: - SplitRenderInfo Nested Proportional Ratios

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
        XCTAssertFalse(renderInfo.allMinimized)
        XCTAssertFalse(renderInfo.splitInfo.isEmpty,
                       "Should have render info for splits with minimized panes")

        // Find the inner split (B|C) — one side should be fully minimized
        let innerSplitInfo = renderInfo.splitInfo.values.first {
            $0.leftFullyMinimized || $0.rightFullyMinimized
        }
        XCTAssertNotNil(innerSplitInfo, "Inner split should have one fully-minimized side")
        XCTAssertEqual(innerSplitInfo?.leftMinimizedPaneIds.count ?? 0
                       + (innerSplitInfo?.rightMinimizedPaneIds.count ?? 0), 1,
                       "Exactly one pane should be in the minimized IDs")
    }
}
