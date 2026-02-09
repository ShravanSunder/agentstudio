import XCTest
@testable import AgentStudio

/// Tests that `Tab` works correctly as a `ResolvableTab` with `ActionResolver`.
/// This validates the Phase 2 conformance added in `ResolvableTab.swift`.
final class ActionResolverTabConformanceTests: XCTestCase {

    // MARK: - Helper

    private func makeTab(sessionIds: [UUID], activeSessionId: UUID? = nil) -> Tab {
        guard let first = sessionIds.first else {
            fatalError("Need at least one session ID")
        }
        if sessionIds.count == 1 {
            return Tab(sessionId: first)
        }

        // Build layout by inserting subsequent sessions
        var layout = Layout(sessionId: first)
        for i in 1..<sessionIds.count {
            layout = layout.inserting(
                sessionId: sessionIds[i],
                at: sessionIds[i - 1],
                direction: .horizontal,
                position: .after
            )
        }
        return Tab(layout: layout, activeSessionId: activeSessionId ?? first)
    }

    // MARK: - ResolvableTab Protocol Conformance

    func test_tab_conformsToResolvableTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Assert — basic properties
        XCTAssertEqual(tab.activePaneId, sessionId)
        XCTAssertEqual(tab.allPaneIds, [sessionId])
        XCTAssertFalse(tab.isSplit)
    }

    func test_tab_multiSession_isSplit() {
        // Arrange
        let ids = [UUID(), UUID(), UUID()]
        let tab = makeTab(sessionIds: ids)

        // Assert
        XCTAssertTrue(tab.isSplit)
        XCTAssertEqual(Set(tab.allPaneIds), Set(ids))
    }

    func test_tab_activePaneId_returnsActiveSessionId() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids, activeSessionId: ids[1])

        // Assert
        XCTAssertEqual(tab.activePaneId, ids[1])
    }

    // MARK: - ActionResolver.resolve with Tab

    func test_resolve_closeTab_withTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let result = ActionResolver.resolve(
            command: .closeTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .closeTab(tabId: tab.id))
    }

    func test_resolve_closePane_withTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let result = ActionResolver.resolve(
            command: .closePane, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .closePane(tabId: tab.id, paneId: sessionId))
    }

    func test_resolve_splitRight_withTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let result = ActionResolver.resolve(
            command: .splitRight, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .newTerminal,
            targetTabId: tab.id,
            targetPaneId: sessionId,
            direction: .right
        ))
    }

    func test_resolve_splitBelow_withTab() {
        // Arrange
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let result = ActionResolver.resolve(
            command: .splitBelow, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .insertPane(
            source: .newTerminal,
            targetTabId: tab.id,
            targetPaneId: sessionId,
            direction: .down
        ))
    }

    func test_resolve_nextTab_withTabs() {
        // Arrange
        let tab1 = Tab(sessionId: UUID())
        let tab2 = Tab(sessionId: UUID())

        // Act — from tab2 wraps to tab1
        let result = ActionResolver.resolve(
            command: .nextTab, tabs: [tab1, tab2], activeTabId: tab2.id
        )

        // Assert
        XCTAssertEqual(result, .selectTab(tabId: tab1.id))
    }

    func test_resolve_prevTab_withTabs() {
        // Arrange
        let tab1 = Tab(sessionId: UUID())
        let tab2 = Tab(sessionId: UUID())

        // Act — from tab1 wraps to tab2
        let result = ActionResolver.resolve(
            command: .prevTab, tabs: [tab1, tab2], activeTabId: tab1.id
        )

        // Assert
        XCTAssertEqual(result, .selectTab(tabId: tab2.id))
    }

    func test_resolve_selectTabByIndex_withTabs() {
        // Arrange
        let tab1 = Tab(sessionId: UUID())
        let tab2 = Tab(sessionId: UUID())
        let tab3 = Tab(sessionId: UUID())
        let tabs = [tab1, tab2, tab3]

        // Act & Assert
        XCTAssertEqual(
            ActionResolver.resolve(command: .selectTab1, tabs: tabs, activeTabId: nil),
            .selectTab(tabId: tab1.id)
        )
        XCTAssertEqual(
            ActionResolver.resolve(command: .selectTab2, tabs: tabs, activeTabId: nil),
            .selectTab(tabId: tab2.id)
        )
        XCTAssertNil(
            ActionResolver.resolve(command: .selectTab4, tabs: tabs, activeTabId: nil)
        )
    }

    func test_resolve_breakUpTab_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids)

        // Act
        let result = ActionResolver.resolve(
            command: .breakUpTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .breakUpTab(tabId: tab.id))
    }

    func test_resolve_extractPaneToTab_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids, activeSessionId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .extractPaneToTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .extractPaneToTab(tabId: tab.id, paneId: ids[0]))
    }

    func test_resolve_equalizePanes_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids)

        // Act
        let result = ActionResolver.resolve(
            command: .equalizePanes, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        XCTAssertEqual(result, .equalizePanes(tabId: tab.id))
    }

    // MARK: - Navigation (neighbor/next/previous)

    func test_resolve_focusNextPane_withTab() {
        // Arrange — two sessions in horizontal split
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids, activeSessionId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .focusNextPane, tabs: [tab], activeTabId: tab.id
        )

        // Assert — should find next pane
        XCTAssertEqual(result, .focusPane(tabId: tab.id, paneId: ids[1]))
    }

    func test_resolve_focusPrevPane_withTab() {
        // Arrange — two sessions, active is second
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids, activeSessionId: ids[1])

        // Act
        let result = ActionResolver.resolve(
            command: .focusPrevPane, tabs: [tab], activeTabId: tab.id
        )

        // Assert — should find previous pane
        XCTAssertEqual(result, .focusPane(tabId: tab.id, paneId: ids[0]))
    }

    func test_resolve_focusPaneRight_withTab() {
        // Arrange — two sessions in horizontal split
        let ids = [UUID(), UUID()]
        let tab = makeTab(sessionIds: ids, activeSessionId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneRight, tabs: [tab], activeTabId: tab.id
        )

        // Assert — neighbor to right of ids[0] is ids[1]
        XCTAssertEqual(result, .focusPane(tabId: tab.id, paneId: ids[1]))
    }

    func test_resolve_focusPaneLeft_singlePane_returnsNil() {
        // Arrange — single pane tab
        let sessionId = UUID()
        let tab = Tab(sessionId: sessionId)

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneLeft, tabs: [tab], activeTabId: tab.id
        )

        // Assert — no neighbor
        XCTAssertNil(result)
    }

    // MARK: - Snapshot from Tab

    func test_snapshot_fromTabs() {
        // Arrange
        let ids1 = [UUID(), UUID()]
        let tab1 = makeTab(sessionIds: ids1, activeSessionId: ids1[0])
        let tab2 = Tab(sessionId: UUID())

        // Act
        let snapshot = ActionResolver.snapshot(
            from: [tab1, tab2], activeTabId: tab1.id, isManagementModeActive: false
        )

        // Assert
        XCTAssertEqual(snapshot.tabCount, 2)
        XCTAssertEqual(snapshot.activeTabId, tab1.id)
        XCTAssertEqual(snapshot.tab(tab1.id)?.activePaneId, ids1[0])
        XCTAssertEqual(Set(snapshot.tab(tab1.id)!.paneIds), Set(ids1))
        XCTAssertTrue(snapshot.tab(tab1.id)?.isSplit == true)
        XCTAssertFalse(snapshot.tab(tab2.id)?.isSplit == true)
    }
}
