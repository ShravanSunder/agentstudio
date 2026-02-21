import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class ActionResolverTests {

    // MARK: - Test Helpers

    private func makeSnapshot(
        tabs: [TabSnapshot] = [],
        activeTabId: UUID? = nil
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: tabs,
            activeTabId: activeTabId,
            isManagementModeActive: false
        )
    }

    private func makeSinglePaneTab(tabId: UUID = UUID(), paneId: UUID = UUID()) -> TabSnapshot {
        TabSnapshot(id: tabId, paneIds: [paneId], activePaneId: paneId)
    }

    private func makeMultiPaneTab(tabId: UUID = UUID(), paneIds: [UUID]? = nil) -> TabSnapshot {
        let ids = paneIds ?? [UUID(), UUID()]
        return TabSnapshot(id: tabId, paneIds: ids, activePaneId: ids.first)
    }

    // MARK: - resolveDrop: Multi-pane tab → mergeTab

    @Test

    func test_resolveDrop_multiPaneTab_returnsMergeTab() {
        // Arrange
        let sourceTabId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeMultiPaneTab(tabId: sourceTabId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: sourceTabId
            ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .right,
            state: snapshot
        )

        // Assert
        #expect(
            result
                == .mergeTab(
                    sourceTabId: sourceTabId,
                    targetTabId: targetTabId,
                    targetPaneId: targetPaneId,
                    direction: .right
                ))
    }

    // MARK: - resolveDrop: Single-pane tab → insertPane

    @Test

    func test_resolveDrop_singlePaneTab_returnsInsertPane() {
        // Arrange
        let sourceTabId = UUID()
        let sourcePaneId = UUID()
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let sourceTab = makeSinglePaneTab(tabId: sourceTabId, paneId: sourcePaneId)
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [sourceTab, targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: sourceTabId
            ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .left,
            state: snapshot
        )

        // Assert
        #expect(
            result
                == .insertPane(
                    source: .existingPane(paneId: sourcePaneId, sourceTabId: sourceTabId),
                    targetTabId: targetTabId,
                    targetPaneId: targetPaneId,
                    direction: .left
                ))
    }

    // MARK: - resolveDrop: New terminal → insertPane

    @Test

    func test_resolveDrop_newTerminal_returnsInsertPane() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(kind: .newTerminal)

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .right,
            state: snapshot
        )

        // Assert
        #expect(
            result
                == .insertPane(
                    source: .newTerminal,
                    targetTabId: targetTabId,
                    targetPaneId: targetPaneId,
                    direction: .right
                ))
    }

    // MARK: - resolveDrop: Source tab not found → nil

    @Test

    func test_resolveDrop_sourceTabNotFound_returnsNil() {
        // Arrange
        let targetTabId = UUID()
        let targetPaneId = UUID()
        let targetTab = makeSinglePaneTab(tabId: targetTabId, paneId: targetPaneId)
        let snapshot = makeSnapshot(tabs: [targetTab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: UUID()
            ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: .right,
            state: snapshot
        )

        // Assert
        #expect((result) == nil)
    }

    // MARK: - resolveDrop: Self-drop produces mergeTab (validator rejects)

    @Test

    func test_resolveDrop_selfDrop_multiPane_producesMergeTab() {
        // Arrange — dropping a multi-pane tab onto its own pane
        let tabId = UUID()
        let paneIds = [UUID(), UUID()]
        let tab = makeMultiPaneTab(tabId: tabId, paneIds: paneIds)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(
            kind: .existingTab(
                tabId: tabId
            ))

        // Act
        let result = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: paneIds[0],
            destinationTabId: tabId,
            zone: .right,
            state: snapshot
        )

        // Assert — resolver produces the action, validator will reject it
        #expect(
            result
                == .mergeTab(
                    sourceTabId: tabId,
                    targetTabId: tabId,
                    targetPaneId: paneIds[0],
                    direction: .right
                ))

        // Verify validator rejects self-merge
        let validation = ActionValidator.validate(result!, state: snapshot)
        if case .failure(.selfTabMerge) = validation { return }
        Issue.record("Expected selfTabMerge error from validator")
    }

    // MARK: - resolve(command:) — Tab Lifecycle

    @Test

    func test_resolve_closeTab_returnsCloseTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .closeTab(tabId: tabId))
    }

    @Test

    func test_resolve_breakUpTab_returnsBreakUpTabWithActiveId() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .breakUpTab, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .breakUpTab(tabId: tabId))
    }

    @Test

    func test_resolve_nextTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from last tab wraps to first
        let result = ActionResolver.resolve(
            command: .nextTab, tabs: [tab1, tab2], activeTabId: tab2Id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab1Id))
    }

    @Test

    func test_resolve_prevTab_wrapsAround() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act — from first tab wraps to last
        let result = ActionResolver.resolve(
            command: .prevTab, tabs: [tab1, tab2], activeTabId: tab1Id
        )

        // Assert
        #expect(result == .selectTab(tabId: tab2Id))
    }

    @Test

    func test_resolve_selectTabByIndex_returnsCorrectTab() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let tab3Id = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab2 = MockTab(id: tab2Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tab3 = MockTab(id: tab3Id, activePaneId: UUID(), allPaneIds: [UUID()])
        let tabs = [tab1, tab2, tab3]

        // Act & Assert
        #expect(ActionResolver.resolve(command: .selectTab1, tabs: tabs, activeTabId: nil) == .selectTab(tabId: tab1Id))
        #expect(ActionResolver.resolve(command: .selectTab3, tabs: tabs, activeTabId: nil) == .selectTab(tabId: tab3Id))
        // Out of range
        #expect((ActionResolver.resolve(command: .selectTab4, tabs: tabs, activeTabId: nil)) == nil)
    }

    // MARK: - resolve(command:) — Pane Lifecycle

    @Test

    func test_resolve_closePane_returnsClosePaneWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)

        // Assert
        #expect(result == .closePane(tabId: tabId, paneId: paneId))
    }

    @Test

    func test_resolve_extractPaneToTab_returnsExtractWithActivePane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .extractPaneToTab, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .extractPaneToTab(tabId: tabId, paneId: paneId))
    }

    @Test

    func test_resolve_equalizePanes_returnsEqualizeWithActiveTab() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act
        let result = ActionResolver.resolve(
            command: .equalizePanes, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .equalizePanes(tabId: tabId))
    }

    // MARK: - resolve(command:) — Pane Focus

    @Test

    func test_resolve_focusPaneLeft_findsNeighbor() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.neighbors = [paneA: [.left: paneB]]

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneLeft, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .focusPane(tabId: tabId, paneId: paneB))
    }

    @Test

    func test_resolve_focusPaneRight_noNeighbor_returnsNil() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA])
        // No neighbors configured

        // Act
        let result = ActionResolver.resolve(
            command: .focusPaneRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect((result) == nil)
    }

    @Test

    func test_resolve_focusNextPane_usesNextPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneA, allPaneIds: [paneA, paneB])
        tab.nextPanes = [paneA: paneB]

        // Act
        let result = ActionResolver.resolve(
            command: .focusNextPane, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .focusPane(tabId: tabId, paneId: paneB))
    }

    @Test

    func test_resolve_focusPrevPane_usesPreviousPaneId() {
        // Arrange
        let tabId = UUID()
        let paneA = UUID()
        let paneB = UUID()
        var tab = MockTab(id: tabId, activePaneId: paneB, allPaneIds: [paneA, paneB])
        tab.previousPanes = [paneB: paneA]

        // Act
        let result = ActionResolver.resolve(
            command: .focusPrevPane, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(result == .focusPane(tabId: tabId, paneId: paneA))
    }

    // MARK: - resolve(command:) — Split

    @Test

    func test_resolve_splitRight_returnsInsertPane() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .splitRight, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect(
            result
                == .insertPane(
                    source: .newTerminal,
                    targetTabId: tabId,
                    targetPaneId: paneId,
                    direction: .right
                ))
    }

    @Test

    func test_resolve_splitBelow_returnsNil() {
        // Vertical splits disabled (drawers own bottom space)
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = MockTab(id: tabId, activePaneId: paneId, allPaneIds: [paneId])

        // Act
        let result = ActionResolver.resolve(
            command: .splitBelow, tabs: [tab], activeTabId: tabId
        )

        // Assert
        #expect((result) == nil)
    }

    // MARK: - resolve(command:) — Edge Cases

    @Test

    func test_resolve_noActiveTab_returnsNil() {
        // Arrange
        let tab = MockTab(id: UUID(), activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — all commands requiring activeTabId return nil
        #expect((ActionResolver.resolve(command: .closeTab, tabs: [tab], activeTabId: nil)) == nil)
        #expect((ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: nil)) == nil)
        #expect((ActionResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: nil)) == nil)
        #expect((ActionResolver.resolve(command: .focusPaneLeft, tabs: [tab], activeTabId: nil)) == nil)
    }

    @Test

    func test_resolve_nonPaneCommand_returnsNil() {
        // Arrange
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: UUID(), allPaneIds: [UUID()])

        // Act & Assert — non-structural commands return nil
        #expect((ActionResolver.resolve(command: .addRepo, tabs: [tab], activeTabId: tabId)) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .toggleSidebar, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .newFloatingTerminal, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .filterSidebar, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .openNewTerminalInTab, tabs: [tab], activeTabId: tabId
            )) == nil)
        // Webview/OAuth commands are non-pane commands
        #expect(
            (ActionResolver.resolve(
                command: .openWebview, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .signInGitHub, tabs: [tab], activeTabId: tabId
            )) == nil)
        #expect(
            (ActionResolver.resolve(
                command: .signInGoogle, tabs: [tab], activeTabId: tabId
            )) == nil)
    }

    @Test

    func test_resolve_noActivePaneId_returnsNil() {
        // Arrange — tab exists but has no activePaneId
        let tabId = UUID()
        let tab = MockTab(id: tabId, activePaneId: nil, allPaneIds: [UUID()])

        // Act & Assert — commands needing active pane return nil
        #expect((ActionResolver.resolve(command: .closePane, tabs: [tab], activeTabId: tabId)) == nil)
        #expect((ActionResolver.resolve(command: .splitRight, tabs: [tab], activeTabId: tabId)) == nil)
    }

    // MARK: - snapshot(from:) with MockTab

    @Test

    func test_snapshot_fromMockTabs_capturesCorrectState() {
        // Arrange
        let tab1Id = UUID()
        let tab2Id = UUID()
        let pane1 = UUID()
        let pane2a = UUID()
        let pane2b = UUID()
        let tab1 = MockTab(id: tab1Id, activePaneId: pane1, allPaneIds: [pane1])
        let tab2 = MockTab(id: tab2Id, activePaneId: pane2a, allPaneIds: [pane2a, pane2b])

        // Act
        let snapshot = ActionResolver.snapshot(
            from: [tab1, tab2], activeTabId: tab1Id, isManagementModeActive: false
        )

        // Assert
        #expect(snapshot.tabCount == 2)
        #expect(snapshot.activeTabId == tab1Id)
        #expect(snapshot.tab(tab1Id)?.paneIds == [pane1])
        #expect(snapshot.tab(tab2Id)?.paneIds == [pane2a, pane2b])
        #expect(snapshot.tab(tab2Id)?.activePaneId == pane2a)
        #expect(snapshot.tab(tab2Id)?.isSplit == true)
        #expect(!(snapshot.tab(tab1Id)?.isSplit == true))
    }

    // MARK: - resolveDrop: Zone → direction mapping

    @Test

    func test_resolveDrop_zoneMapping() {
        // Arrange
        let tabId = UUID()
        let paneId = UUID()
        let tab = makeSinglePaneTab(tabId: tabId, paneId: paneId)
        let snapshot = makeSnapshot(tabs: [tab])
        let payload = SplitDropPayload(kind: .newTerminal)

        let zoneMappings: [(DropZone, SplitNewDirection)] = [
            (.left, .left),
            (.right, .right),
        ]

        for (zone, expectedDirection) in zoneMappings {
            // Act
            let result = ActionResolver.resolveDrop(
                payload: payload,
                destinationPaneId: paneId,
                destinationTabId: tabId,
                zone: zone,
                state: snapshot
            )

            // Assert
            #expect(
                result
                    == .insertPane(
                        source: .newTerminal,
                        targetTabId: tabId,
                        targetPaneId: paneId,
                        direction: expectedDirection
                    ), "Zone \(zone) should map to direction \(expectedDirection)")
        }
    }
}
