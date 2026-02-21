import Testing
import Foundation

@testable import AgentStudio

/// Tests that `Tab` works correctly as a `ResolvableTab` with `ActionResolver`.
/// This validates the Phase 2 conformance added in `ResolvableTab.swift`.
@Suite(.serialized)
final class ActionResolverTabConformanceTests {

    // MARK: - ResolvableTab Protocol Conformance

    @Test

    func test_tab_conformsToResolvableTab() {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Assert — basic properties
        #expect(tab.activePaneId == paneId)
        #expect(tab.allPaneIds == [paneId])
        #expect(!(tab.isSplit))
    }

    @Test

    func test_tab_multiPane_isSplit() {
        // Arrange
        let ids = [UUID(), UUID(), UUID()]
        let tab = makeTab(paneIds: ids)

        // Assert
        #expect(tab.isSplit)
        #expect(Set(tab.allPaneIds) == Set(ids))
    }

    @Test

    func test_tab_activePaneId_returnsActivePaneId() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids, activePaneId: ids[1])

        // Assert
        #expect(tab.activePaneId == ids[1])
    }

    // MARK: - ActionResolver.resolve with Tab

    @Test

    func test_resolve_closeTab_withTab() {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let result = ActionResolver.resolve(
            command: .closeTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .closeTab(tabId: tab.id))
    }

    @Test

    func test_resolve_closePane_withTab() {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let result = ActionResolver.resolve(
            command: .closePane, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .closePane(tabId: tab.id, paneId: paneId))
    }

    @Test

    func test_resolve_splitRight_withTab() {
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let result = ActionResolver.resolve(
            command: .splitRight, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .insertPane(
                source: .newTerminal,
                targetTabId: tab.id,
                targetPaneId: paneId,
                direction: .right
            ))
    }

    @Test

    func test_resolve_splitBelow_withTab_returnsNil() {
        // Vertical splits disabled (drawers own bottom space)
        // Arrange
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let result = ActionResolver.resolve(
            command: .splitBelow, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect((result) == nil)
    }

    @Test

    func test_resolve_nextTab_withTabs() {
        // Arrange
        let tab1 = Tab(paneId: UUID())
        let tab2 = Tab(paneId: UUID())

        // Act — from tab2 wraps to tab1
        let result = ActionResolver.resolve(
            command: .nextTab, tabs: [tab1, tab2], activeTabId: tab2.id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab1.id))
    }

    @Test

    func test_resolve_prevTab_withTabs() {
        // Arrange
        let tab1 = Tab(paneId: UUID())
        let tab2 = Tab(paneId: UUID())

        // Act — from tab1 wraps to tab2
        let result = ActionResolver.resolve(
            command: .prevTab, tabs: [tab1, tab2], activeTabId: tab1.id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab2.id))
    }

    @Test

    func test_resolve_selectTabByIndex_withTabs() {
        // Arrange
        let tab1 = Tab(paneId: UUID())
        let tab2 = Tab(paneId: UUID())
        let tab3 = Tab(paneId: UUID())
        let tabs = [tab1, tab2, tab3]

        // Act & Assert
        #expect(ActionResolver.resolve(command: .selectTab1, tabs: tabs, activeTabId: nil) == .selectTab(tabId: tab1.id))
        #expect(ActionResolver.resolve(command: .selectTab2, tabs: tabs, activeTabId: nil) == .selectTab(tabId: tab2.id))
        #expect((ActionResolver.resolve(command: .selectTab4, tabs: tabs, activeTabId: nil)) == nil)
    }

    @Test

    func test_resolve_breakUpTab_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids)

        // Act
        let result = ActionResolver.resolve(
            command: .breakUpTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .breakUpTab(tabId: tab.id))
    }

    @Test

    func test_resolve_extractPaneToTab_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids, activePaneId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .extractPaneToTab, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .extractPaneToTab(tabId: tab.id, paneId: ids[0]))
    }

    @Test

    func test_resolve_equalizePanes_withTab() {
        // Arrange
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids)

        // Act
        let result = ActionResolver.resolve(
            command: .equalizePanes, tabs: [tab], activeTabId: tab.id
        )

        // Assert
        #expect(result == .equalizePanes(tabId: tab.id))
    }

    // MARK: - Navigation (neighbor/next/previous)

    @Test

    func test_resolve_focusNextPane_withTab() {
        // Arrange — two panes in horizontal split
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids, activePaneId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .focusNextPane, tabs: [tab], activeTabId: tab.id
        )

        // Assert — should find next pane
        #expect(result == .focusPane(tabId: tab.id, paneId: ids[1]))
    }

    @Test

    func test_resolve_focusPrevPane_withTab() {
        // Arrange — two panes, active is second
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids, activePaneId: ids[1])

        // Act
        let result = ActionResolver.resolve(
            command: .focusPrevPane, tabs: [tab], activeTabId: tab.id
        )

        // Assert — should find previous pane
        #expect(result == .focusPane(tabId: tab.id, paneId: ids[0]))
    }

    @Test

    func test_resolve_focusPaneRight_withTab() {
        // Arrange — two panes in horizontal split
        let ids = [UUID(), UUID()]
        let tab = makeTab(paneIds: ids, activePaneId: ids[0])

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneRight, tabs: [tab], activeTabId: tab.id
        )

        // Assert — neighbor to right of ids[0] is ids[1]
        #expect(result == .focusPane(tabId: tab.id, paneId: ids[1]))
    }

    @Test

    func test_resolve_focusPaneLeft_singlePane_returnsNil() {
        // Arrange — single pane tab
        let paneId = UUID()
        let tab = Tab(paneId: paneId)

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneLeft, tabs: [tab], activeTabId: tab.id
        )

        // Assert — no neighbor
        #expect((result) == nil)
    }

    // MARK: - Snapshot from Tab

    @Test

    func test_snapshot_fromTabs() {
        // Arrange
        let ids1 = [UUID(), UUID()]
        let tab1 = makeTab(paneIds: ids1, activePaneId: ids1[0])
        let tab2 = Tab(paneId: UUID())

        // Act
        let snapshot = ActionResolver.snapshot(
            from: [tab1, tab2], activeTabId: tab1.id, isManagementModeActive: false
        )

        // Assert
        #expect(snapshot.tabCount == 2)
        #expect(snapshot.activeTabId == tab1.id)
        #expect(snapshot.tab(tab1.id)?.activePaneId == ids1[0])
        #expect(Set(snapshot.tab(tab1.id)!.paneIds) == Set(ids1))
        #expect(snapshot.tab(tab1.id)?.isSplit == true)
        #expect(!(snapshot.tab(tab2.id)?.isSplit == true))
    }
}
